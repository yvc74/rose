with System.Storage_Elements;

with Rose.Interfaces.Block_Device.Client.Table;
with Rose.Devices.Partitions;

with Rose.Console_IO;

package body Rose.Devices.GPT is

   use Rose.Interfaces.Block_Device;

   GPT_Magic : constant Rose.Words.Word_64 := 16#5452_4150_2049_4645#;

   type GPT_Header is
      record
         Magic                 : Rose.Words.Word_64 := GPT_Magic;
         Revision              : Rose.Words.Word_32 := 16#0001_0000#;
         Header_Size           : Rose.Words.Word_32 := 16#0000_005C#;
         Header_CRC            : Rose.Words.Word_32 := 0;
         Reserved_Zero         : Rose.Words.Word_32 := 0;
         Current_LBA           : Block_Address_Type := 0;
         Backup_LBA            : Block_Address_Type := 0;
         First_Usable_LBA      : Block_Address_Type := 0;
         Last_Usable_LBA       : Block_Address_Type := 0;
         Disk_GUID_Lo          : Rose.Words.Word_64 := 0;
         Disk_GUID_Hi          : Rose.Words.Word_64 := 0;
         Start_Partition_LBA   : Block_Address_Type := 0;
         Partition_Entry_Count : Rose.Words.Word_32 := 0;
         Partition_Entry_Size  : Rose.Words.Word_32 := 16#0000_0080#;
         Partition_Array_CRC   : Rose.Words.Word_32 := 0;
      end record
   with Size => 92 * 8;

   type GPT_Partition_Entry is
      record
         Partition_Type_Low  : Rose.Words.Word_64 := 0;
         Partition_Type_High : Rose.Words.Word_64 := 0;
         Partition_Id_Low    : Rose.Words.Word_64 := 0;
         Partition_Id_High   : Rose.Words.Word_64 := 0;
         First_LBA           : Block_Address_Type := 0;
         Last_LBA            : Block_Address_Type := 0;
         Flags               : Rose.Words.Word_64 := 0;
         Name                : String (1 .. 72) :=
                                 (others => Character'Val (0));
      end record
     with Size => 128 * 8;

   type GPT_Partition_Entry_Array is
     array (Rose.Words.Word_32 range <>) of GPT_Partition_Entry;

   type GPT_Record is
      record
         Header     : GPT_Header;
         Parts      : GPT_Partition_Entry_Array (0 .. 15);
         Block_Size : Block_Size_Type;
         Dirty      : Boolean := False;
      end record;

   package Cached_Table is
     new Rose.Interfaces.Block_Device.Client.Table (8, GPT_Record);

   GPT_Data          : GPT_Record;

   procedure Check_Cached
     (Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client);

   procedure Save_Changes
     (Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client);

   function Partition_Entries_Per_Block
     (Block_Size : Block_Size_Type)
      return Rose.Words.Word_32;

   procedure Read_Header
     (Block_Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client;
      Header       : out GPT_Header);

   procedure Write_Header
     (Block_Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client;
      Header       : GPT_Header);

   procedure Write_Partition_Entries
     (Block_Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client;
      Entries      : GPT_Partition_Entry_Array);

   -------------------
   -- Add_Partition --
   -------------------

   procedure Add_Partition
     (Block_Device        : Client.Block_Device_Client;
      First_Block         : Block_Address_Type;
      Last_Block          : Block_Address_Type;
      Partition_Type_Low  : Rose.Words.Word_64;
      Partition_Type_High : Rose.Words.Word_64;
      Partition_Flags     : Rose.Words.Word_64;
      Partition_Name      : String)
   is
      use Rose.Words;
      Header            : GPT_Header renames GPT_Data.Header;
      Part              : GPT_Partition_Entry renames
                            GPT_Data.Parts (Header.Partition_Entry_Count);
   begin

      Check_Cached (Block_Device);

      if not Has_GPT (Block_Device) then
         Rose.Console_IO.Put_Line ("add_partition: no gpt header");
         return;
      end if;

      Part :=
        GPT_Partition_Entry'
          (Partition_Type_Low  => Partition_Type_Low,
           Partition_Type_High => Partition_Type_High,
           Partition_Id_Low    => Word_64 (Header.Partition_Entry_Count),
           Partition_Id_High   => 0,
           First_LBA           => First_Block,
           Last_LBA            => Last_Block,
           Flags               => Partition_Flags,
           Name                => <>);

      declare
         Index : Natural := 0;
      begin
         for Ch of Partition_Name loop
            Index := Index + 1;
            Part.Name (Index) := Ch;
         end loop;
      end;

      Header.Partition_Entry_Count := Header.Partition_Entry_Count + 1;
      Save_Changes (Block_Device);
   end Add_Partition;

   ------------------
   -- Check_Cached --
   ------------------

   procedure Check_Cached
     (Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client)
   is
   begin
      if Cached_Table.Contains (Device) then
         Cached_Table.Get_Element (Device, GPT_Data);
         return;
      end if;

      declare
         use Rose.Words;
         Block_Size  : Block_Size_Type;
         Block_Count : Block_Address_Type;
      begin
         Client.Get_Parameters (Device, Block_Count, Block_Size);

         declare
            Entry_Count       : constant Word_32 :=
                                  Partition_Entries_Per_Block (Block_Size);
            Partition_Entries : GPT_Partition_Entry_Array
              (0 .. Entry_Count - 1);
            Partition_Buffer  : System.Storage_Elements.Storage_Array
              (1 .. System.Storage_Elements.Storage_Count (Block_Size));
            pragma Import (Ada, Partition_Buffer);
            for Partition_Buffer'Address use Partition_Entries'Address;
         begin
            GPT_Data.Block_Size := Block_Size;
            Read_Header (Device, GPT_Data.Header);
            if GPT_Data.Header.Magic = GPT_Magic then
               if GPT_Data.Header.Partition_Entry_Count > 0 then
                  Client.Read_Blocks
                    (Device, 2, 1, Partition_Buffer);
                  for I in 0 .. GPT_Data.Header.Partition_Entry_Count - 1 loop
                     GPT_Data.Parts (I) := Partition_Entries (I);
                  end loop;
               end if;
            end if;
            Cached_Table.Insert (Device, GPT_Data);
         end;
      end;
   end Check_Cached;

   -----------
   -- Flush --
   -----------

   procedure Flush
     (Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client)
   is
      use type Rose.Words.Word_32;
   begin
      Check_Cached (Device);
      if GPT_Data.Dirty then
         Write_Header (Device, GPT_Data.Header);
         Write_Partition_Entries
           (Device,
            GPT_Data.Parts (0 .. GPT_Data.Header.Partition_Entry_Count - 1));
         GPT_Data.Dirty := False;
         Save_Changes (Device);
      end if;
   end Flush;

   ---------------------------
   -- Get_Partition_Details --
   ---------------------------

   procedure Get_Partition_Details
     (Block_Device        :
      Rose.Interfaces.Block_Device.Client.Block_Device_Client;
      Partition_Index     : Positive;
      First_Block         : out
        Rose.Interfaces.Block_Device.Block_Address_Type;
      Last_Block          : out
        Rose.Interfaces.Block_Device.Block_Address_Type;
      Partition_Type_Low  : out Rose.Words.Word_64;
      Partition_Type_High : out Rose.Words.Word_64;
      Partition_Flags     : out Rose.Words.Word_64;
      Partition_Name      : out String;
      Partition_Name_Last : out Natural)
   is
   begin
      Check_Cached (Block_Device);

      declare
         use Rose.Words;
         Index : constant Word_32 := Word_32 (Partition_Index) - 1;
         Part : GPT_Partition_Entry renames
                  GPT_Data.Parts (Index);
      begin
         First_Block := Part.First_LBA;
         Last_Block  := Part.Last_LBA;
         Partition_Type_Low := Part.Partition_Type_Low;
         Partition_Type_High := Part.Partition_Type_High;
         Partition_Flags := Part.Flags;
         Partition_Name :=
           Part.Name
             (1 .. Natural'Min (Partition_Name'Length, Part.Name'Length));
         Partition_Name_Last := 0;
         for Ch of Partition_Name loop
            exit when Character'Pos (Ch) = 0;
            Partition_Name_Last := Partition_Name_Last + 1;
         end loop;
      end;
   end Get_Partition_Details;

   -------------
   -- Has_GPT --
   -------------

   function Has_GPT
     (Block_Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client)
      return Boolean
   is
      use type Rose.Words.Word_64;
   begin
      Check_Cached (Block_Device);
      return GPT_Data.Header.Magic = GPT_Magic;
   end Has_GPT;

   --------------------
   -- Initialize_GPT --
   --------------------

   procedure Initialize_GPT
     (Block_Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client)
   is
      Header : constant GPT_Header := (others => <>);
   begin
      Check_Cached (Block_Device);
      GPT_Data.Header := Header;
      GPT_Data.Dirty := True;
      Save_Changes (Block_Device);
   end Initialize_GPT;

   ---------------------
   -- Partition_Count --
   ---------------------

   function Partition_Count
     (Block_Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client)
      return Natural
   is
   begin
      Check_Cached (Block_Device);
      return Natural (GPT_Data.Header.Partition_Entry_Count);
   end Partition_Count;

   ---------------------------------
   -- Partition_Entries_Per_Block --
   ---------------------------------

   function Partition_Entries_Per_Block
     (Block_Size : Block_Size_Type)
      return Rose.Words.Word_32
   is
      use Rose.Words;
   begin
      return Word_32 (Block_Size) / 128;
   end Partition_Entries_Per_Block;

   -----------------
   -- Read_Header --
   -----------------

   procedure Read_Header
     (Block_Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client;
      Header       : out GPT_Header)
   is
      Block_Size  : Block_Size_Type;
      Block_Count : Block_Address_Type;
   begin
      Client.Get_Parameters (Block_Device, Block_Count, Block_Size);

      declare
         use System.Storage_Elements;
         Header_Storage : Storage_Array (1 .. Storage_Count (Block_Size));
         Header_Record  : GPT_Header;
         pragma Import (Ada, Header_Record);
         for Header_Record'Address use Header_Storage'Address;
      begin
         Rose.Interfaces.Block_Device.Client.Read_Blocks
           (Block_Device, 1, 1, Header_Storage);
         Header := Header_Record;
      end;
   end Read_Header;

   ----------------------------
   -- Report_Partition_Table --
   ----------------------------

   procedure Report_Partition_Table
     (Block_Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client)
   is
      use Rose.Words;
      Header : GPT_Header renames GPT_Data.Header;
      Partition_Entries : GPT_Partition_Entry_Array renames
                            GPT_Data.Parts;
   begin

      Check_Cached (Block_Device);

      if not Has_GPT (Block_Device) then
         Rose.Console_IO.Put_Line ("No GPT block found");
         return;
      end if;

      if Header.Partition_Entry_Count = 0 then
         Rose.Console_IO.Put_Line ("No partitions in device");
         return;
      end if;

      Rose.Console_IO.Put_Line
        ("# Name            Start        End      Type      Flags");
      for I in 0 .. Header.Partition_Entry_Count - 1 loop
         Rose.Console_IO.Put (Natural (I));
         Rose.Console_IO.Put (" ");
         declare
            Part : GPT_Partition_Entry renames Partition_Entries (I);
         begin
            for J in 1 .. 15 loop
               declare
                  Ch : constant Character := Part.Name (J);
               begin
                  if Ch = Character'Val (0) then
                     Rose.Console_IO.Put (' ');
                  else
                     Rose.Console_IO.Put (Ch);
                  end if;
               end;
            end loop;

            Rose.Console_IO.Put (Natural (Part.First_LBA), 10);
            Rose.Console_IO.Put (Natural (Part.Last_LBA), 11);
            Rose.Console_IO.Put ("  ");

            declare
               use Rose.Devices.Partitions;
            begin
               if Part.Partition_Type_Low = Swap_Id_Low
                 and then Part.Partition_Type_High = Swap_Id_High
               then
                  Rose.Console_IO.Put
                    ("rose-swap ");
               elsif Part.Partition_Type_Low = Log_Id_Low
                 and then Part.Partition_Type_High = Log_Id_High
               then
                  Rose.Console_IO.Put
                    ("rose-log  ");
               else
                  Rose.Console_IO.Put
                    ("unknown   ");
               end if;

               if (Part.Flags and Active_Swap_Flag) /= 0 then
                  Rose.Console_IO.Put ("A");
               end if;
            end;

         end;
         Rose.Console_IO.New_Line;
      end loop;

   end Report_Partition_Table;

   ------------------
   -- Save_Changes --
   ------------------

   procedure Save_Changes
     (Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client)
   is
   begin
      Cached_Table.Update (Device, GPT_Data);
   end Save_Changes;

   ------------------
   -- Write_Header --
   ------------------

   procedure Write_Header
     (Block_Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client;
      Header       : GPT_Header)
   is
      Block_Size  : Block_Size_Type;
      Block_Count : Block_Address_Type;
   begin
      Client.Get_Parameters (Block_Device, Block_Count, Block_Size);

      declare
         use System.Storage_Elements;
         Header_Storage : Storage_Array (1 .. Storage_Count (Block_Size));
         Header_Record  : GPT_Header;
         pragma Import (Ada, Header_Record);
         for Header_Record'Address use Header_Storage'Address;
      begin
         Header_Record := Header;
         Client.Write_Blocks (Block_Device, 1, 1, Header_Storage);
         Client.Write_Blocks
           (Block_Device, Block_Count - 1, 1, Header_Storage);
      end;
   end Write_Header;

   -----------------------------
   -- Write_Partition_Entries --
   -----------------------------

   procedure Write_Partition_Entries
     (Block_Device : Rose.Interfaces.Block_Device.Client.Block_Device_Client;
      Entries      : GPT_Partition_Entry_Array)
   is
      use Rose.Words;
      Block_Size  : Block_Size_Type;
      Block_Count : Block_Address_Type;
   begin
      Client.Get_Parameters (Block_Device, Block_Count, Block_Size);
      declare
         Entry_Count       : constant Word_32 :=
                               Partition_Entries_Per_Block (Block_Size);
         Partition_Entries : GPT_Partition_Entry_Array (0 .. Entry_Count - 1);
         Block_Storage     : System.Storage_Elements.Storage_Array
           (1 .. System.Storage_Elements.Storage_Count (Block_Size));
         pragma Import (Ada, Block_Storage);
         for Block_Storage'Address use Partition_Entries'Address;
      begin
         Block_Storage := (others => 0);
         Partition_Entries (Entries'Range) := Entries;
         Rose.Interfaces.Block_Device.Client.Write_Blocks
           (Block_Device, 2, 1, Block_Storage);
      end;
   end Write_Partition_Entries;

end Rose.Devices.GPT;
