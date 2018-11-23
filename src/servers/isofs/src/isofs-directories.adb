with System.Storage_Elements;

with Rose.Words;

with Rose.Console_IO;

with Rose.Interfaces.Directory;
with Rose.System_Calls.Server;

package body IsoFS.Directories is

   use Rose.Words;

   Max_Directories : constant := 100;

   subtype ISO_Sector is
     System.Storage_Elements.Storage_Array
       (1 .. ISO_Sector_Size);

   type Directory_Date_Time is array (1 .. 7) of Word_8;

   type Directory_Entry is
      record
         Length                           : Word_8;
         Extended_Attribute_Record_Length : Word_8;
         Extent_Location_LSB              : Word_32;
         Extent_Location_MSB              : Word_32;
         Extent_Size_LSB                  : Word_32;
         Extent_Size_MSB                  : Word_32;
         Recording_Date_Time              : Directory_Date_Time;
         File_Flags                       : Word_8;
         Interleaved_File_Unit_Size       : Word_8;
         Interleaved_Gap_Size             : Word_8;
         Volume_Sequence_LSB              : Word_16;
         Volume_Sequence_MSB              : Word_16;
         File_Identifier_Length           : Word_8;
      end record
   with Pack, Size => 33 * 8;

   type Primary_Volume_Sector is
      record
         Sector_Type                   : Word_8;
         Standard_Identifier           : String (1 .. 5);
         Version                       : Word_8;
         Unused_1                      : Word_8;
         System_Identifier             : String (1 .. 32);
         Volume_Identifier             : String (1 .. 32);
         Unused_2                      : Word_64;
         Volume_Space_Size_LSB         : Word_32;
         Volume_Space_Size_MSB         : Word_32;
         Unused_3                      : String (1 .. 32);
         Volume_Set_Size_LSB           : Word_16;
         Volume_Set_Size_MSB           : Word_16;
         Volume_Seq_Nr_LSB             : Word_16;
         Volume_Seq_Nr_MSB             : Word_16;
         Logical_Block_Size_LSB        : Word_16;
         Logical_Block_Size_MSB        : Word_16;
         Path_Table_Size_LSB           : Word_32;
         Path_Table_Size_MSB           : Word_32;
         L_Path_Table_Address          : Word_32;
         Optional_L_Path_Table_Address : Word_32;
         M_Path_Table_Address          : Word_32;
         Optional_M_Path_Table_Address : Word_32;
         Root_Directory_Entry          : Directory_Entry;
         Empty_Root_Directory_Name     : Word_8;
         Volume_Set_Identifier         : String (1 .. 128);
         Publisher_Identifier          : String (1 .. 128);
         Data_Preparer_Identifier      : String (1 .. 128);
         Application_Identifier        : String (1 .. 128);
         Copyright_File_Identifier     : String (1 .. 38);
         Abstract_File_Identifier      : String (1 .. 36);
         Bibliographic_File_Identifier : String (1 .. 37);
         Create_Date_Time              : String (1 .. 17);
         Modification_Date_Time        : String (1 .. 17);
         Expiration_Date_Time          : String (1 .. 17);
         Effective_Date_Time           : String (1 .. 17);
         File_Structure_Version        : Word_8;
         Unused_4                      : Word_8;
         Available                     : String (1 .. 512);
         Reserved                      : String (1 .. 653);
      end record
     with Pack, Size => 2048 * 8;

   type Directory_Caps_Record is
      record
         Valid : Boolean := False;
         Entry_Record          : Directory_Entry;
         Directory_Entry_Count : Rose.Capabilities.Capability := 0;
         Directory_Entry_Name  : Rose.Capabilities.Capability := 0;
         Directory_Entry_Kind  : Rose.Capabilities.Capability := 0;
         Get_Ordinary_File     : Rose.Capabilities.Capability := 0;
         Get_Directory         : Rose.Capabilities.Capability := 0;
         Read_File             : Rose.Capabilities.Capability := 0;
      end record;

   type Directory_Caps_Array is
     array (Directory_Type range 1 .. Max_Directories)
     of Directory_Caps_Record;

   Directory_Caps : Directory_Caps_Array;

   procedure Read_Root_Directory
     (Device : Rose.Devices.Block.Client.Block_Device_Type);

   function New_Cap
     (Directory : Directory_Type;
      Endpoint  : Rose.Objects.Endpoint_Id)
      return Rose.Capabilities.Capability
   is (Rose.System_Calls.Server.Create_Endpoint
       (Create_Endpoint_Cap, Endpoint,
        Rose.Objects.Capability_Identifier (Directory)));

   procedure Create_Cap_Record
     (Directory : Directory_Type;
      Dir_Entry : Directory_Entry);

   -----------------------
   -- Create_Cap_Record --
   -----------------------

   procedure Create_Cap_Record
     (Directory : Directory_Type;
      Dir_Entry : Directory_Entry)
   is
      use Rose.Interfaces.Directory;

      function New_Cap
        (EP : Rose.Objects.Endpoint_Id)
               return Rose.Capabilities.Capability
      is (New_Cap (Directory, EP));

   begin
      Directory_Caps (Directory) :=
        Directory_Caps_Record'
          (Valid                 => True,
           Entry_Record          => Dir_Entry,
           Directory_Entry_Count =>
              New_Cap (Directory_Entry_Count_Endpoint),
           Directory_Entry_Name  =>
              New_Cap (Directory_Entry_Name_Endpoint),
           Directory_Entry_Kind  =>
              New_Cap (Directory_Entry_Kind_Endpoint),
           Get_Ordinary_File     =>
              New_Cap (Get_Ordinary_File_Endpoint),
           Get_Directory         =>
              New_Cap (Get_Directory_Endpoint),
           Read_File             =>
              New_Cap (Read_File_Endpoint));
   end Create_Cap_Record;

   -------------------------
   -- Get_Child_Directory --
   -------------------------

   function Get_Child_Directory
     (Parent     : Directory_Type;
      Child_Name : String)
      return Directory_Type
   is
      pragma Unreferenced (Parent, Child_Name);
   begin
      return No_Directory;
   end Get_Child_Directory;

   ------------------------------
   -- Get_Identified_Directory --
   ------------------------------

   function Get_Identified_Directory
     (Identifier : Rose.Objects.Capability_Identifier)
      return Directory_Type
   is
      Directory : constant Directory_Type := Directory_Type (Identifier);
   begin
      if Directory in 1 .. Max_Directories
        and then Directory_Caps (Directory).Valid
      then
         return Directory;
      else
         return No_Directory;
      end if;
   end Get_Identified_Directory;

   ------------------------
   -- Get_Root_Directory --
   ------------------------

   function Get_Root_Directory
     (Device : Rose.Devices.Block.Client.Block_Device_Type)
      return Directory_Type
   is
   begin
      if not Directory_Caps (Root_Directory).Valid then
         Read_Root_Directory (Device);
      end if;
      if Directory_Caps (Root_Directory).Valid then
         return Root_Directory;
      else
         return No_Directory;
      end if;
   end Get_Root_Directory;

   -------------------------
   -- Read_Root_Directory --
   -------------------------

   procedure Read_Root_Directory
     (Device : Rose.Devices.Block.Client.Block_Device_Type)
   is
      use System.Storage_Elements;
      use Rose.Devices.Block;
      use Rose.Devices.Block.Client;

      Volume_Index : Block_Address_Type := ISO_First_Volume_Sector;
      Sector_Count : constant Block_Address_Type :=
                       Get_Block_Count (Device);
      Found        : Boolean := False;
      Buffer       : ISO_Sector;
   begin
      while Volume_Index < Sector_Count
        and then not Found
      loop

         Read_Block (Device, Volume_Index, Buffer);

         if Buffer (Descriptor_Type_Offset + 1)
           = Primary_Volume_Descriptor
         then
            Found := True;
         else
            Volume_Index := Volume_Index + 1;
         end if;
      end loop;

      if not Found then
         Rose.Console_IO.Put_Line
           ("isofs: cannot find primary volume descriptor");
         return;
      end if;

      declare
         use Rose.Console_IO;
         Volume : Primary_Volume_Sector;
         pragma Import (Ada, Volume);
         for Volume'Address use Buffer'Address;
      begin
         Rose.Console_IO.Put
           ("found volume: ");
         Rose.Console_IO.Put
           (Volume.Volume_Identifier);
         Rose.Console_IO.New_Line;
         Put ("root directory timestamp: ");
         declare
            D : Directory_Date_Time renames
                  Volume.Root_Directory_Entry.Recording_Date_Time;
         begin
            Put (Natural (D (1)) + 1900);
            Put ("-");
            Put (Natural (D (2)), 2, '0');
            Put ("-");
            Put (Natural (D (3)), 2, '0');
            Put (" ");
            Put (Natural (D (4)), 2, '0');
            Put (":");
            Put (Natural (D (5)), 2, '0');
            Put (":");
            Put (Natural (D (6)), 2, '0');
            New_Line;
         end;

         Create_Cap_Record (Root_Directory, Volume.Root_Directory_Entry);

      end;

   end Read_Root_Directory;

   -------------------------
   -- Send_Directory_Caps --
   -------------------------

   procedure Send_Directory_Caps
     (Directory             : Directory_Type;
      Params                : in out Rose.Invocation.Invocation_Record)
   is
      use Rose.System_Calls;
      Caps : Directory_Caps_Record renames Directory_Caps (Directory);
   begin
      Send_Cap (Params, Caps.Directory_Entry_Count);
      Send_Cap (Params, Caps.Directory_Entry_Name);
      Send_Cap (Params, Caps.Directory_Entry_Kind);
      Send_Cap (Params, Caps.Get_Ordinary_File);
      Send_Cap (Params, Caps.Get_Directory);
      Send_Cap (Params, Caps.Read_File);
      Send_Cap (Params, Rose.Capabilities.Null_Capability);
      Send_Cap (Params, Rose.Capabilities.Null_Capability);
   end Send_Directory_Caps;

end IsoFS.Directories;