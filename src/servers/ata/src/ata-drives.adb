with Rose.Console_IO;
with Rose.Devices.Port_IO;

with ATA.Commands;

package body ATA.Drives is

   Drive_Table : array (ATA_Drive_Index) of aliased ATA_Drive_Record;

   function Get (Index : ATA_Drive_Index) return ATA_Drive
   is (Drive_Table (Index)'Access);

   Id_Buffer : array (1 .. 256) of Rose.Words.Word_16;

   ----------------------
   -- Initialize_Drive --
   ----------------------

   procedure Initialize_Drive
     (Index        : ATA_Drive_Index;
      Command_Cap  : Rose.Capabilities.Capability;
      Control_Cap  : Rose.Capabilities.Capability;
      Data_Cap_8   : Rose.Capabilities.Capability;
      Data_Cap_16  : Rose.Capabilities.Capability;
      Base_DMA     : Rose.Words.Word_32;
      Is_Native    : Boolean)
   is
      Identify : ATA.Commands.ATA_Command;

   begin
      Drive_Table (Index) :=
        ATA_Drive_Record'
          (Initialized => True,
           Listening   => False,
           Dead        => False,
           Native      => Is_Native,
           Command_Cap => Command_Cap,
           Control_Cap => Control_Cap,
           Base_DMA    => Base_DMA,
           Block_Size  => 512,
           Block_Count => 0);

      ATA.Commands.Identify
        (Command => Identify,
         Master  => Index in 0 | 2,
         LBA     => False);

      if ATA.Commands.Send_Command
        (Identify, Command_Cap, Control_Cap, Data_Cap_8)
      then

         if not ATA.Commands.Wait_For_Status
           (Data_Cap_8, ATA.Commands.Status_Busy, 0)
         then
            Drive_Table (Index).Dead := True;
            return;
         end if;

         declare
            use Rose.Words;
            Id_4   : constant Rose.Words.Word_8 :=
                       Rose.Devices.Port_IO.Port_In_8
                         (Data_Cap_8, 4);
            Id_5   : constant Rose.Words.Word_8 :=
                       Rose.Devices.Port_IO.Port_In_8
                         (Data_Cap_8, 5);
         begin
            Rose.Console_IO.Put ("identity: ");
            Rose.Console_IO.Put (Id_4);
            Rose.Console_IO.Put (" ");
            Rose.Console_IO.Put (Id_5);
            if Id_4 = 16#14# and then Id_5 = 16#EB# then
               Rose.Console_IO.Put (" (atapi)");
            elsif Id_4 = 16#3C# and then Id_5 = 16#c3# then
               Rose.Console_IO.Put (" (sata)");
            else
               Rose.Console_IO.Put (" (unknown)");
            end if;
            Rose.Console_IO.New_Line;

            for I in 1 .. 256 loop
               declare
                  D : constant Rose.Words.Word_16 :=
                        Rose.Devices.Port_IO.Port_In_16 (Data_Cap_16);
               begin
                  Id_Buffer (I) := D;
               end;
            end loop;

            Rose.Console_IO.Put ("ata: hd");
            Rose.Console_IO.Put (Natural (Index));
            Rose.Console_IO.Put (": ");

            Rose.Console_IO.Put (Natural (Id_Buffer (2)));
            Rose.Console_IO.Put ("/");
            Rose.Console_IO.Put (Natural (Id_Buffer (4)));
            Rose.Console_IO.Put ("/");
            Rose.Console_IO.Put (Natural (Id_Buffer (7)));

            Rose.Console_IO.Put (": ");
            if (Id_Buffer (84) and 2 ** 10) /= 0 then
               Rose.Console_IO.Put ("lba48 ");
            end if;

            declare
               Sector_Count : constant Word_32 :=
                                Word_32 (Id_Buffer (61))
                                + 65536 * Word_32 (Id_Buffer (62));
            begin
               if Sector_Count > 0 then
                  Rose.Console_IO.Put ("lba28 ");
                  Rose.Console_IO.Put (Natural (Sector_Count));
                  Rose.Console_IO.Put (" ");
                  Drive_Table (Index).Block_Count :=
                    Rose.Devices.Block.Block_Address_Type (Sector_Count);
               end if;
            end;

            Rose.Console_IO.Put ("size: ");
            declare
               Size : constant Word_64 :=
                        Word_64 (Drive_Table (Index).Block_Count)
                        * Word_64 (Drive_Table (Index).Block_Size);
            begin
               if Size < 2 ** 32 then
                  Rose.Console_IO.Put (Natural (Size / 2 ** 20));
                  Rose.Console_IO.Put ("M");
               else
                  Rose.Console_IO.Put (Natural (Size / 2 ** 30));
                  Rose.Console_IO.Put ("G");
               end if;
            end;

            Rose.Console_IO.Put (" ");

            for I in 24 .. 42 loop
               declare
                  S : constant String (1 .. 2) :=
                        (Character'Val (Id_Buffer (I) / 256),
                         Character'Val (Id_Buffer (I) mod 256));
               begin
                  for Ch of S loop
                     if Ch in ' ' .. '~' then
                        Rose.Console_IO.Put (Ch);
                     else
                        Rose.Console_IO.Put ('.');
                     end if;
                  end loop;
               end;
            end loop;

            Rose.Console_IO.New_Line;

         end;

         Drive_Table (Index).Listening := True;
      else
         Rose.Console_IO.Put ("unable to initialise hd");
         Rose.Console_IO.Put (Natural (Index));
         Rose.Console_IO.New_Line;
         Drive_Table (Index).Dead := True;
      end if;

   end Initialize_Drive;

   -------------
   -- Is_Dead --
   -------------

   function Is_Dead (Drive : ATA_Drive) return Boolean is
   begin
      return Drive.Dead;
   end Is_Dead;

   --------------------
   -- Is_Initialized --
   --------------------

   function Is_Initialized (Drive : ATA_Drive) return Boolean is
   begin
      return Drive.Initialized;
   end Is_Initialized;

   ------------------
   -- Is_Listening --
   ------------------

   function Is_Listening (Drive : ATA_Drive) return Boolean is
   begin
      return Drive.Listening;
   end Is_Listening;

end ATA.Drives;
