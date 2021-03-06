with Rose.Devices.Port_IO;
with Rose.Interfaces.Block_Device;
with Rose.Console_IO;

package body ATA.Commands is

   Max_Status_Wait  : constant := 400;
   Warn_Status_Wait : constant := 100;

   Selected_Drive      : ATA.Drives.ATA_Drive_Index := 0;
   Have_Selected_Drive : Boolean := False;

   function Check_Drive_OK
     (Drive : ATA.Drives.ATA_Drive)
      return Boolean;

   function To_Select_Drive
     (Master  : Boolean;
      LBA     : Boolean;
      Address : Rose.Devices.Block.Block_Address_Type := 0)
      return Rose.Words.Word_8;

   function Select_Drive
     (Drive : ATA.Drives.ATA_Drive)
      return Boolean;

   procedure Sector_Command
     (Drive   : ATA.Drives.ATA_Drive;
      Write   : Boolean;
      LBA     : Rose.Devices.Block.Block_Address_Type;
      Command : out ATA_Command);

   procedure Read_Sectors_ATAPI
     (Drive   : ATA.Drives.ATA_Drive;
      Address : Rose.Devices.Block.Block_Address_Type;
      Count   : Positive;
      Sector  : out System.Storage_Elements.Storage_Array;
      Success : out Boolean);

   --------------------
   -- Check_Drive_OK --
   --------------------

   function Check_Drive_OK
     (Drive : ATA.Drives.ATA_Drive)
      return Boolean
   is
      use ATA.Drives;
      Status : constant ATA_Status :=
                 ATA_Status
                   (Rose.Devices.Port_IO.Port_In_8
                      (Data_8_Port (Drive), 7));
   begin
      if (Status and Status_Error) /= 0 then
         Log (Drive, "check_drive_ok: error status");
         return False;
      end if;
      return True;
   end Check_Drive_OK;

   ----------------------------
   -- Current_Selected_Drive --
   ----------------------------

   function Current_Selected_Drive return ATA.Drives.ATA_Drive_Index is
   begin
      return Selected_Drive;
   end Current_Selected_Drive;

   -----------
   -- Flush --
   -----------

   procedure Flush
     (Drive : ATA.Drives.ATA_Drive)
   is
      Command : constant ATA_Command :=
                  (Command => ATA_Flush,
                   Master  => ATA.Drives.Is_Master (Drive),
                   others  => <>);
   begin
      if not Send_Command (Drive, Command) then
         Rose.Console_IO.Put_Line ("cannot flush drive");
      end if;
   end Flush;

   ------------------------
   -- Initialize_Command --
   ------------------------

   procedure Initialize_Command
     (Item    : out ATA_Command;
      Command : ATA_Command_Type;
      Master  : Boolean;
      Use_LBA : Boolean := True)
   is
   begin
      Item := (Command => Command, Master => Master, Use_LBA => Use_LBA,
               others  => <>);
   end Initialize_Command;

   -----------------
   -- Log_Command --
   -----------------

   procedure Log_Command
     (Drive   : ATA.Drives.ATA_Drive;
      Message : String;
      Command : ATA_Command)
   is
      use Rose.Console_IO;
   begin
      Put ("ata: ");
      Put ("hd");
      Put (Character'Val (48 + Natural (ATA.Drives.Drive_Index (Drive))));
      Put (": ");
      Put (Message);
      Put (": ");
      Put (Rose.Words.Word_8 (Command.Command));
      Put (" ");
      Put (if Command.Master then " master" else " slave");
      Put (if Command.Use_LBA then " lba" else " chs");
      Put (if Command.Atapi then " atapi" else " ata");
      Put (" ");
      Put (Natural (Command.LBA));
      New_Line;
   end Log_Command;

   ----------------------
   -- Poll_Status_Bits --
   ----------------------

   function Poll_Status_Bits
     (Drive : ATA.Drives.ATA_Drive;
      Busy  : Boolean := False;
      DRQ   : Boolean := False)
      return Boolean
   is
      Status : ATA.Drives.ATA_Status;
   begin

      for I in 1 .. 4 loop
         Status :=
           ATA.Drives.ATA_Status
             (Rose.Devices.Port_IO.Port_In_8
                (ATA.Drives.Data_8_Port (Drive), 7));
      end loop;

      for I in 1 .. Max_Status_Wait loop

         Status :=
           ATA.Drives.ATA_Status
             (Rose.Devices.Port_IO.Port_In_8
                (ATA.Drives.Data_8_Port (Drive), 7));

         declare
            use ATA.Drives;
            Busy_Bit : constant Boolean :=
                         (Status and Status_Busy) /= 0;
            DRQ_Bit  : constant Boolean :=
                         (Status and Status_DRQ) /= 0;
            Err_Bit  : constant Boolean :=
                         (Status and Status_Error) /= 0;
         begin
            if Err_Bit then
               return False;
            elsif Busy_Bit = Busy and then
              (not DRQ or else DRQ_Bit)
            then
               if I > Warn_Status_Wait then
                  Log (Drive, "excessive polls in Poll_Status_Bits");
               end if;
               return True;
            end if;
         end;

      end loop;

      declare
         use ATA.Drives;
         procedure Put (Mask  : ATA_Status;
                        Text  : String);
         ---------
         -- Put --
         ---------

         procedure Put (Mask  : ATA_Status;
                        Text  : String)
         is
         begin
            if (Status and Mask) = Mask then
               Rose.Console_IO.Put (" ");
               Rose.Console_IO.Put (Text);
            end if;
         end Put;

      begin
         Rose.Console_IO.Put ("ata: hd");
         Rose.Console_IO.Put
           (Character'Val (48 + ATA.Drives.Drive_Index (Drive)));
         Rose.Console_IO.Put (": poll-status-bits failed; last status");
         Put (Status_Error, "ERR");
         Put (Status_DRQ, "DRQ");
         Put (Status_Busy, "BSY");
      end;

      Rose.Console_IO.Put ("; expected ");
      Rose.Console_IO.Put (if Busy then "" else " not");
      Rose.Console_IO.Put (" BSY,");
      Rose.Console_IO.Put (if DRQ then "" else " not");
      Rose.Console_IO.Put (" DRQ");
      Rose.Console_IO.New_Line;
      return False;

   end Poll_Status_Bits;

   -----------------
   -- Read_Sector --
   -----------------

   procedure Read_Sectors
     (Drive   : ATA.Drives.ATA_Drive;
      Address : Rose.Devices.Block.Block_Address_Type;
      Count   : Positive;
      Sectors : out System.Storage_Elements.Storage_Array;
      Success : out Boolean)
   is
      use System.Storage_Elements;
      Index : Storage_Offset := Sectors'First - 1;
      Command : ATA_Command;
      Data_Port : constant Rose.Capabilities.Capability :=
                    ATA.Drives.Data_16_Read_Port (Drive);
   begin

      Success := False;

      if ATA.Drives.Is_Dead (Drive) then
         ATA.Drives.Log (Drive, "drive is dead");
      end if;

      if not Select_Drive (Drive) then
         ATA.Drives.Log (Drive, "Read_Sectors: select drive failed");
      end if;

      if ATA.Drives.Is_Atapi (Drive) then
         Read_Sectors_ATAPI (Drive, Address, Count, Sectors, Success);
         return;
      end if;

      for I in 1 .. Count loop
         declare
            use Rose.Interfaces.Block_Device;
            Next : constant Block_Address_Type :=
                     Address + Block_Address_Type (I - 1);
         begin
            Sector_Command (Drive, False, Next, Command);

            if not Send_Command (Drive, Command) then
               ATA.Drives.Log (Drive, "sending read command failed");
               return;
            end if;

            if not ATA.Drives.Wait_For_Interrupt (Drive) then
               ATA.Drives.Log
                 (Drive, "read: ready interrupt failed to arrive");
               ATA.Drives.Set_Dead (Drive);
               return;
            end if;

            if not Poll_Status_Bits
              (Drive,
               Busy => False,
               DRQ  => True)
            then
               ATA.Drives.Log (Drive, "read: waiting for DRQ failed");
               ATA.Drives.Set_Dead (Drive);
               return;
            end if;

            for I in 1 .. 256 loop
               declare
                  use Rose.Words;
                  D : constant Rose.Words.Word_16 :=
                        Rose.Devices.Port_IO.Port_In_16 (Data_Port);
               begin
                  Index := Index + 1;
                  Sectors (Index) := Storage_Element (D mod 256);
                  Index := Index + 1;
                  Sectors (Index) := Storage_Element (D / 256);
               end;
            end loop;

            if not Check_Drive_OK (Drive) then
               ATA.Drives.Log (Drive, "error detected after read");
               return;
            end if;
         end;
      end loop;

      Success := True;

   end Read_Sectors;

   -----------------------
   -- Read_Sector_ATAPI --
   -----------------------

   procedure Read_Sectors_ATAPI
     (Drive   : ATA.Drives.ATA_Drive;
      Address : Rose.Devices.Block.Block_Address_Type;
      Count   : Positive;
      Sector  : out System.Storage_Elements.Storage_Array;
      Success : out Boolean)
   is
      pragma Unreferenced (Count);
      use Rose.Interfaces.Block_Device;
      use Rose.Words;
      use ATA.Drives;
      use System.Storage_Elements;
      Index         : Storage_Offset := Sector'First - 1;
      Atapi_Command : array (1 .. 6) of Word_16 :=
                        (1 => Word_16 (ATAPI_Read), others => 0);
      Data          : Rose.Devices.Port_IO.Word_8_Data_Array (1 .. 6);
      Command_Port  : constant Rose.Capabilities.Capability :=
                        ATA.Drives.Command_Port (Drive);
      Status_Port   : constant Rose.Capabilities.Capability :=
                        ATA.Drives.Data_8_Port (Drive);
      Block_Size    : constant Word_16 :=
                        Word_16 (ATA.Drives.Block_Size (Drive));
      Data_Out      : constant Rose.Capabilities.Capability :=
                        Data_16_Write_Port (Drive);
      Data_In      : constant Rose.Capabilities.Capability :=
                        Data_16_Read_Port (Drive);
   begin

      Success := False;

      Data (1) := (1, 0);
      Data (2) := (4, Word_8 (Block_Size mod 256));
      Data (3) := (5, Word_8 (Block_Size / 256));
      Data (4) := (7, Word_8 (ATAPI_Packet));

      Rose.Devices.Port_IO.Port_Out_8
        (Port => Command_Port,
         Data => Data (1 .. 4));

      if not Poll_Status_Bits (Drive) then
         ATA.Drives.Log (Drive, "unresponsive after sending ATA command");
         ATA.Drives.Set_Dead (Drive);
         return;
      end if;

      Atapi_Command (5) := 1 * 256;  --  1 sector
      Atapi_Command (2) := Word_16 (Address / 2 ** 24)
        + Word_16 (Address / 2 ** 16) * 2 ** 8;
      Atapi_Command (3) :=
        Word_16 (Address / 256)
        + 256 * Word_16 (Address mod 256);

      for W of Atapi_Command loop
         Rose.Devices.Port_IO.Port_Out_16
           (Port  => Data_Out,
            Value => W);
      end loop;

      if not Wait_For_Interrupt (Drive) then
         ATA.Drives.Log (Drive, "no IRQ after sending ATAPI packet");
         ATA.Drives.Set_Dead (Drive);
         return;
      end if;

      declare
         Size_Lo : constant Word_8 :=
                     Rose.Devices.Port_IO.Port_In_8
                       (Status_Port, 4);
         Size_Hi : constant Word_8 :=
                     Rose.Devices.Port_IO.Port_In_8
                       (Status_Port, 5);
         Available_Size : constant Word_16 :=
                            Word_16 (Size_Lo)
                            + 256 * Word_16 (Size_Hi);
      begin
         if Available_Size /= Block_Size then
            Rose.Console_IO.Put ("ata: expected ");
            Rose.Console_IO.Put (Natural (Block_Size));
            Rose.Console_IO.Put (" bytes, but drive reported ");
            Rose.Console_IO.Put (Natural (Available_Size));
            Rose.Console_IO.New_Line;
            return;
         end if;
      end;

      for I in 1 .. Block_Size / 2 loop
         declare
            D : constant Rose.Words.Word_16 :=
                  Rose.Devices.Port_IO.Port_In_16 (Data_In);
         begin
            Index := Index + 1;
            Sector (Index) := Storage_Element (D mod 256);
            Index := Index + 1;
            Sector (Index) := Storage_Element (D / 256);
         end;
      end loop;

      if not Wait_For_Interrupt (Drive) then
         ATA.Drives.Log (Drive, "no IRQ after reading ATAPI data");
         ATA.Drives.Set_Dead (Drive);
         return;
      end if;

      if not Poll_Status_Bits (Drive) then
         return;
      end if;

      Success := True;

   end Read_Sectors_ATAPI;

   --------------------
   -- Sector_Command --
   --------------------

   procedure Sector_Command
     (Drive   : ATA.Drives.ATA_Drive;
      Write   : Boolean;
      LBA     : Rose.Devices.Block.Block_Address_Type;
      Command : out ATA_Command)
   is
   begin
      if ATA.Drives.Is_Atapi (Drive) then
         Command := (Command        => ATAPI_Packet,
                     Master         => ATA.Drives.Is_Master (Drive),
                     Atapi          => True,
                     Max_Byte_Count => 2048,
                     LBA            => LBA,
                     Sector_Count   => 1,
                     others         => <>);
      else
         Command := (Command      =>
                       (if not Write
                        then ATA_Read_Sectors
                        else ATA_Write_Sectors),
                     Master       => ATA.Drives.Is_Master (Drive),
                     Use_LBA      => True,
                     Sector_Count => 1,
                     LBA          => LBA,
                     others       => <>);
      end if;
   end Sector_Command;

   ------------------
   -- Select_Drive --
   ------------------

   function Select_Drive
     (Drive : ATA.Drives.ATA_Drive)
      return Boolean
   is
      use type ATA.Drives.ATA_Drive_Index;
   begin

      if Have_Selected_Drive
        and then Selected_Drive = ATA.Drives.Drive_Index (Drive)
      then
         return True;
      end if;

      if not Poll_Status_Bits (Drive) then
         ATA.Drives.Log
           (Drive, "select-drive: pre poll status bits failed");
         return False;
      end if;

      Rose.Devices.Port_IO.Port_Out_8
        (ATA.Drives.Command_Port (Drive), R_Select_Drive,
         To_Select_Drive
           (Master  => ATA.Drives.Is_Master (Drive),
            LBA     => True,
            Address => 0));

      if not Poll_Status_Bits (Drive) then
         ATA.Drives.Log
           (Drive, "select-drive: post poll status bits failed");
         return False;
      end if;

      Selected_Drive := ATA.Drives.Drive_Index (Drive);
      Have_Selected_Drive := True;

      if False then
         ATA.Drives.Log (ATA.Drives.Get (Selected_Drive), "selected");
      end if;

      return True;

   end Select_Drive;

   ------------------
   -- Send_Command --
   ------------------

   function Send_Command
     (Drive        : ATA.Drives.ATA_Drive;
      Command      : ATA_Command;
      Log          : Boolean := False)
      return Boolean
   is
      Command_Port : constant Rose.Capabilities.Capability :=
                       ATA.Drives.Command_Port (Drive);
   begin

      if not Select_Drive (Drive) then
         return False;
      end if;

      declare
         use Rose.Words;
         Data : Rose.Devices.Port_IO.Word_8_Data_Array (1 .. 6);
      begin
         Data (1) := (1, 0);
         Data (2) := (2, Command.Sector_Count);

         if Command.Use_LBA then
            declare
               LBA_28 : constant Word_32 := Word_32 (Command.LBA);
            begin
               Data (3) := (3, Word_8 (LBA_28 mod 256));
               Data (4) := (4, Word_8 (LBA_28 / 256 mod 256));
               Data (5) := (5, Word_8 (LBA_28 / 65536 mod 256));
            end;
         else
            Data (3) := (3, Command.Sector);
            Data (4) := (4, Word_8 (Command.Cylinder mod 256));
            Data (5) := (5, Word_8 (Command.Cylinder / 256));
         end if;

         Data (6) := (7, Rose.Words.Word_8 (Command.Command));

         if False and then Log then
            Rose.Console_IO.Put ("command:");
            for Item of Data loop
               Rose.Console_IO.Put (" ");
               Rose.Console_IO.Put (Item.Data);
            end loop;
            Rose.Console_IO.New_Line;
         end if;

         Rose.Devices.Port_IO.Port_Out_8
           (Port => Command_Port,
            Data => Data);
      end;

      return True;
   end Send_Command;

   ------------------
   -- Send_Control --
   ------------------

   procedure Send_Control
     (Drive : ATA.Drives.ATA_Drive;
      Value : Rose.Words.Word_8)
   is
      Command_Port : constant Rose.Capabilities.Capability :=
                       ATA.Drives.Command_Port (Drive);
   begin
      Rose.Devices.Port_IO.Port_Out_8
        (Command_Port, R_Control, Value);
   end Send_Control;

   ---------------------
   -- To_Select_Drive --
   ---------------------

   function To_Select_Drive
     (Master  : Boolean;
      LBA     : Boolean;
      Address : Rose.Devices.Block.Block_Address_Type := 0)
      return Rose.Words.Word_8
   is
      use Rose.Words;
   begin
      return Boolean'Pos (LBA) * 2 ** 6
        + Boolean'Pos (not Master) * 2 ** 4
        + 2 ** 7 + 2 ** 5
        + Word_8 (Word_32 (Address) / 2 ** 24);
   end To_Select_Drive;

   ---------------------
   -- Wait_For_Status --
   ---------------------

--     function Wait_For_Status
--       (Drive     : ATA.Drives.ATA_Drive;
--        Mask      : ATA.Drives.ATA_Status;
--        Value     : ATA.Drives.ATA_Status)
--        return Boolean
--     is
--        use type ATA.Drives.ATA_Status;
--        X : ATA.Drives.ATA_Status := 0;
--        Data_Port : constant Rose.Capabilities.Capability :=
--                      ATA.Drives.Data_8_Port (Drive);
--     begin
--        for I in 1 .. 400 loop
--           if I mod 100 = 0 then
--              Rose.Console_IO.Put_Line ("waiting ...");
--           end if;
--           X := ATA.Drives.ATA_Status
--             (Rose.Devices.Port_IO.Port_In_8 (Data_Port, 7));
--           if (X and Mask) = Value then
--              return True;
--           end if;
--           if (X and 1) /= 0 then
--              return False;
--           end if;
--        end loop;
--        if True then
--           Rose.Console_IO.Put ("wait for status: giving up; last status ");
--           Rose.Console_IO.Put (Rose.Words.Word_8 (X));
--           Rose.Console_IO.Put ("; expected ");
--           Rose.Console_IO.Put (Rose.Words.Word_8 (Mask));
--           Rose.Console_IO.Put (" ");
--           Rose.Console_IO.Put (Rose.Words.Word_8 (Value));
--           Rose.Console_IO.New_Line;
--        end if;
--        return False;
--     end Wait_For_Status;

   ------------------
   -- Write_Sector --
   ------------------

   procedure Write_Sectors
     (Drive   : ATA.Drives.ATA_Drive;
      Address : Rose.Devices.Block.Block_Address_Type;
      Count   : Positive;
      Sectors : System.Storage_Elements.Storage_Array;
      Success : out Boolean)
   is
      use System.Storage_Elements;
      Index   : Storage_Offset := Sectors'First;
      Data_Port : constant Rose.Capabilities.Capability :=
                    ATA.Drives.Data_16_Write_Port (Drive);
      Command : ATA_Command;
   begin

      Success := False;

      if ATA.Drives.Is_Dead (Drive) then
         ATA.Drives.Log (Drive, "drive is dead");
         return;
      end if;

      for I in 1 .. Count loop
         declare
            use Rose.Interfaces.Block_Device;
            Next : constant Block_Address_Type :=
                     Address + Block_Address_Type (I - 1);
         begin
            Sector_Command (Drive, True, Next, Command);

            if not Send_Command (Drive, Command) then
               ATA.Drives.Log (Drive, "sending write command failed");
               return;
            end if;

            if not Poll_Status_Bits (Drive, DRQ => True) then
               ATA.Drives.Log (Drive, "unresponsive after write");
               ATA.Drives.Set_Dead (Drive);
               return;
            end if;

            for I in 1 .. 256 loop
               declare
                  use Rose.Words;
                  D : constant Word_16 :=
                        Word_16 (Sectors (Index)) +
                        256 * Word_16 (Sectors (Index + 1));
               begin
                  Rose.Devices.Port_IO.Port_Out_16 (Data_Port, D);
                  Index := Index + 2;
               end;
            end loop;

            if not ATA.Drives.Wait_For_Interrupt (Drive) then
               ATA.Drives.Log (Drive, "did not get interupt after write");
               return;
            end if;

            if not Check_Drive_OK (Drive) then
               ATA.Drives.Log (Drive, "error detected after write");
               return;
            end if;

         end;
      end loop;
      Success := True;

   end Write_Sectors;

end ATA.Commands;
