with Rose.Objects;
with Rose.Words;

with Rose.Devices.Partitions;

with Rose.Interfaces.Block_Device;
with Rose.Interfaces.Constructor;
with Rose.Interfaces.File_System;
with Rose.Interfaces.Storage;
with Rose.Interfaces.Timer;
with Rose.Interfaces.Timeout;

with Rose.Interfaces.Partitions.Client;

with Rose.Interfaces.Exec;
with Rose.Interfaces.Executable;
with Rose.Interfaces.Installer;
with Rose.Interfaces.Memory;

with Rose.Invocation;
with Rose.System_Calls;

with Init.Calls;
with Init.Installer;

package body Init.Run is

   NL : constant Character := Character'Val (10);

   Memory_Priority        : constant := 3;
   Device_Driver_Priority : constant := 4;
   File_System_Priority   : constant := 10;
   Low_Priority           : constant := 12;

   Console_Module   : constant := 2;
   Mem_Module       : constant := 3;
   PCI_Module       : constant := 4;
   ATA_Module       : constant := 5;
   Store_Module     : constant := 6;
   ISOFS_Module     : constant := 7;
   Restore_Module   : constant := 8;
   Scan_Module      : constant := 9;
   Partition_Module : constant := 10;
   Elf_Module       : constant := 11;
   Timer_Module     : constant := 12;
   Cap_Set_Module   : constant := 13;

   --------------
   -- Run_Init --
   --------------

   procedure Run_Init is
      use Rose.Capabilities, Rose.Objects, Rose.Words;
      Boot_Cap             : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap, (8, 1, 0, 0));
      Reserve_Cap          : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap, (10, 1, 0, 0));
      Console_Mem_Cap      : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap,
                                  (1, 1, 16#0000_00B8#, 16#FF00_0000#));
      Console_Cursor_Cap   : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap,
                                  (16#0000_000E#, 3, 16#03D4#, 16#03D5#));
      Create_Endpoint_Cap  : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap, (2, 1, 0, 0));
      Delete_Cap           : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap, (2, 30, 0, 0));
      Rescind_Cap          : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap, (2, 29, 0, 0));
      Exit_Cap             : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap, (2, 31, 0, 0));
      Copy_Console_Cap     : Rose.Capabilities.Capability;
      Console_Id           : Rose.Objects.Object_Id;
      Console_Write_Cap    : Rose.Capabilities.Capability :=
                               Null_Capability;
      Mem_Region_Count_Cap : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap, (10, 2, 0, 0));
      Mem_Get_Region_Cap   : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap, (10, 3, 0, 0));
      Page_On_Cap          : constant Rose.Capabilities.Capability :=
                               Init.Calls.Call
                                 (Create_Cap, (7, 1, 0, 0));

      Mem_Cap              : Rose.Capabilities.Capability;
      Timer_Cap            : Rose.Capabilities.Capability := Null_Capability;
      PCI_Cap              : Rose.Capabilities.Capability;

      Cap_Set_Cap          : Rose.Capabilities.Capability;

      Hd0_Cap              : Rose.Capabilities.Capability;
      Hd1_Cap              : Rose.Capabilities.Capability;

      Storage_Cap          : Rose.Capabilities.Capability;
      Add_Storage_Cap      : Rose.Capabilities.Capability;
      Reserve_Storage_Cap  : Rose.Capabilities.Capability;

      Launch_Elf_Cap       : Rose.Capabilities.Capability;
      Install_Media_FS     : Rose.Capabilities.Capability;
      Install_Receiver     : Rose.Capabilities.Capability;
      Install_Endpoint     : Rose.Capabilities.Capability;

      Active_Swap_Cap   : Rose.Capabilities.Capability := 0;
      Inactive_Swap_Cap : Rose.Capabilities.Capability := 0;
      Log_Cap           : Rose.Capabilities.Capability := 0;

      Receive_Timeout  : Rose.Capabilities.Capability;
      Send_Timeout     : Rose.Capabilities.Capability;

      function Copy_Cap_From_Process
        (Copy_Cap   : Rose.Capabilities.Capability;
         Endpoint   : Rose.Objects.Endpoint_Id;
         Identifier : Rose.Objects.Capability_Identifier := 0)
         return Rose.Capabilities.Capability;

      procedure Load_Partition
        (Client            : Rose.Interfaces.Partitions
         .Client.Partitions_Client;
         Device_Cap        : Rose.Capabilities.Capability;
         Index             : Positive);

      function Is_Swap_Partition (Low, High : Word_64) return Boolean
      is (Low = Rose.Devices.Partitions.Swap_Id_Low
          and then High = Rose.Devices.Partitions.Swap_Id_High);

      function Is_Log_Partition (Low, High : Word_64) return Boolean
      is (Low = Rose.Devices.Partitions.Log_Id_Low
          and then High = Rose.Devices.Partitions.Log_Id_High);

      procedure Wait (Milliseconds : Natural);

      ---------------------------
      -- Copy_Cap_From_Process --
      ---------------------------

      function Copy_Cap_From_Process
        (Copy_Cap   : Rose.Capabilities.Capability;
         Endpoint   : Rose.Objects.Endpoint_Id;
         Identifier : Rose.Objects.Capability_Identifier := 0)
         return Rose.Capabilities.Capability
      is
         Data : constant Init.Calls.Array_Of_Words :=
                  (Word_32 (Word_64 (Endpoint) mod 2 ** 32),
                   Word_32 (Word_64 (Endpoint) / 2 ** 32),
                   Word_32 (Identifier));
         Cap  : Capability :=
                  Init.Calls.Call (Copy_Cap, Data);
         Hex_Digits : constant String := "0123456789ABCDEF";
         Retry_Message : String :=
                           "init: failed to copy endpoint; retrying "
                           & "            " & NL;
         Fail_Message  : constant String :=
                           "init: failed to copy endpoint; giving up"
                           & NL;
         It            : Word_64 := Rose.Words.Word_64 (Endpoint);
      begin
         for I in 1 .. 12 loop
            Retry_Message (Retry_Message'Last - I) :=
              Hex_Digits (Natural (It mod 16) + 1);
            It := It / 16;
         end loop;

         if Timer_Cap = Null_Capability then
            for I in 1 .. 16 loop
               exit when Cap /= Null_Capability;
               Init.Calls.Send_String
                 (Console_Write_Cap, Retry_Message);
               Cap := Init.Calls.Call (Copy_Cap, Data);
            end loop;
         else
            for I in 1 .. 4 loop
               exit when Cap /= Null_Capability;
               Init.Calls.Send_String
                 (Console_Write_Cap, Retry_Message);
               Wait (1000);
               Cap := Init.Calls.Call (Copy_Cap, Data);
            end loop;
         end if;

         if Cap = Null_Capability then
            if Console_Write_Cap /= Null_Capability then
               Init.Calls.Send_String
                 (Console_Write_Cap, Fail_Message);
            end if;
            Init.Calls.Send (Exit_Cap);
         end if;

         return Cap;
      end Copy_Cap_From_Process;

      --------------------
      -- Load_Partition --
      --------------------

      procedure Load_Partition
        (Client            : Rose.Interfaces.Partitions
         .Client.Partitions_Client;
         Device_Cap        : Rose.Capabilities.Capability;
         Index             : Positive)
      is
         Partition_Type_Low  : Rose.Words.Word_64;
         Partition_Type_High : Rose.Words.Word_64;
         Partition_Flags     : Rose.Words.Word_64;
         Start_Address       : Rose.Words.Word_64;
         Length              : Rose.Words.Word_64;
         Id                  : Rose.Objects.Object_Id;
         Is_Active_Swap      : Boolean := False;
         Is_Inactive_Swap    : Boolean := False;
         Is_Log              : Boolean := False;
         Block_Size          : Rose.Words.Word;
         Active_Swap_Flag    : constant Word_64 :=
                                 Rose.Devices.Partitions.Active_Swap_Flag;
      begin
         Rose.Interfaces.Partitions.Client.Get_Partition
           (Client, Index, Partition_Type_Low,
            Partition_Type_High, Partition_Flags,
            Start_Address, Length);

         if Is_Swap_Partition (Partition_Type_Low, Partition_Type_High) then
            Block_Size := 4096;
            if (Partition_Flags and Active_Swap_Flag) /= 0 then
               Is_Active_Swap := True;
               if Active_Swap_Cap /= 0 then
                  return;
               end if;
            else
               Is_Inactive_Swap := True;
               if Inactive_Swap_Cap /= 0 then
                  return;
               end if;
            end if;
         elsif Is_Log_Partition (Partition_Type_Low, Partition_Type_High) then
            Block_Size := 512;
            Is_Log := True;
            if Log_Cap /= 0 then
               return;
            end if;

         else
            return;
         end if;

         Id :=
           Init.Calls.Launch_Boot_Module
             (Boot_Cap, Partition_Module, Device_Driver_Priority,
              Create_Endpoint_Cap, Cap_Set_Cap,
              (Console_Write_Cap,
               Device_Cap),
              (Rose.Words.Word (Start_Address),
               Rose.Words.Word (Start_Address + Length),
               Block_Size));

         declare
            Copy_Id_Cap   : constant Rose.Capabilities.Capability :=
                              Init.Calls.Call
                                (Create_Cap,
                                 (9, 1,
                                  Word (Id mod 2 ** 32),
                                  Word (Id / 2 ** 32)));
            Interface_Cap : constant Rose.Capabilities.Capability :=
                              Copy_Cap_From_Process
                                (Copy_Id_Cap,
                                 Rose.Interfaces.Block_Device
                                 .Block_Device_Interface);
         begin
            if Is_Active_Swap then
               Active_Swap_Cap := Interface_Cap;
            elsif Is_Inactive_Swap then
               Inactive_Swap_Cap := Interface_Cap;
            elsif Is_Log then
               Log_Cap := Interface_Cap;
            end if;
         end;

      end Load_Partition;

      ----------
      -- Wait --
      ----------

      procedure Wait (Milliseconds : Natural) is
         Control_Cap : constant Rose.Capabilities.Capability :=
                         Init.Calls.Call
                           (Timer_Cap, Send_Timeout,
                            (1 => Rose.Words.Word (Milliseconds)));
      begin
         pragma Unreferenced (Control_Cap);
         Init.Calls.Receive (Receive_Timeout);
      end Wait;

   begin
      Init.Calls.Send (Reserve_Cap, (16#0000_1000#, 16#0009_F000#));
      Console_Id :=
        Init.Calls.Launch_Boot_Module
          (Boot_Cap, Console_Module, Low_Priority,
           Create_Endpoint_Cap,
           Rose.Capabilities.Null_Capability,
           (Console_Mem_Cap,
            Console_Cursor_Cap));
      Copy_Console_Cap :=
        Init.Calls.Call
          (Create_Cap,
           (9, 1, Word (Console_Id mod 2 ** 32), Word (Console_Id / 2 ** 32)));

      Console_Write_Cap :=
        Copy_Cap_From_Process (Copy_Console_Cap, 16#C025_0130#);

      declare
         Cap_Set_Id : constant Rose.Objects.Object_Id :=
                        Init.Calls.Launch_Boot_Module
                          (Boot_Cap, Cap_Set_Module,
                           Device_Driver_Priority,
                           Create_Endpoint_Cap,
                           Rose.Capabilities.Null_Capability,
                           (1 => Console_Write_Cap));
         Copy_Cap_Set_Cap : constant Rose.Capabilities.Capability :=
                              Init.Calls.Call
                                (Create_Cap,
                                 (9, 1,
                                  Word (Cap_Set_Id mod 2 ** 32),
                                  Word (Cap_Set_Id / 2 ** 32)));
      begin
         Cap_Set_Cap :=
           Copy_Cap_From_Process
             (Copy_Cap_Set_Cap,
              Rose.Interfaces.Constructor.Create_Endpoint);
      end;

      declare
         Mem_Id : constant Rose.Objects.Object_Id :=
                    Init.Calls.Launch_Boot_Module
                      (Boot_Cap, Mem_Module, Memory_Priority,
                       Create_Endpoint_Cap,
                       Cap_Set_Cap,
                       (Console_Write_Cap,
                        Mem_Region_Count_Cap, Mem_Get_Region_Cap,
                        Page_On_Cap));
         Copy_Mem_Cap : constant Rose.Capabilities.Capability :=
                          Init.Calls.Call
                            (Create_Cap,
                             (9, 1,
                              Word (Mem_Id mod 2 ** 32),
                              Word (Mem_Id / 2 ** 32)));
      begin
         Mem_Cap :=
           Copy_Cap_From_Process
             (Copy_Mem_Cap, Rose.Interfaces.Memory.Memory_Interface);
      end;

      declare
         Set_Timeout_Cap : constant Rose.Capabilities.Capability :=
                             Init.Calls.Call
                               (Create_Cap,
                                (7, 6, 0, 0));
         Get_Ticks_Cap   : constant Rose.Capabilities.Capability :=
                             Init.Calls.Call
                               (Create_Cap,
                                (7, 7, 0, 0));
         Timer_Id       : constant Rose.Objects.Object_Id :=
                            Init.Calls.Launch_Boot_Module
                               (Boot_Cap, Timer_Module, Device_Driver_Priority,
                                Create_Endpoint_Cap, Cap_Set_Cap,
                               (Console_Write_Cap,
                                Set_Timeout_Cap, Get_Ticks_Cap));
         Copy_Timeout_Cap : constant Rose.Capabilities.Capability :=
                              Init.Calls.Call
                                (Create_Cap,
                                 (9, 1,
                                  Word (Timer_Id mod 2 ** 32),
                                  Word (Timer_Id / 2 ** 32)));
         Timer_Caps       : Init.Calls.Array_Of_Capabilities (1 .. 2);
         Control_Cap      : Rose.Capabilities.Capability with Unreferenced;

      begin
         Timer_Cap :=
           Copy_Cap_From_Process
             (Copy_Timeout_Cap, Rose.Interfaces.Timer.Set_Timer_Endpoint);

         Init.Calls.Call
           (Cap         => Create_Endpoint_Cap,
            Data        =>
              (Rose.Words.Word_32
                   (Rose.Interfaces.Timeout.On_Timeout_Endpoint
                    mod 2 ** 32),
               Rose.Words.Word_32
                 (Rose.Interfaces.Timeout.On_Timeout_Endpoint / 2 ** 32)),
            Result_Caps => Timer_Caps);

         Receive_Timeout := Timer_Caps (1);
         Send_Timeout := Timer_Caps (2);

      end;

      declare
         Command_Port_Out_Cap : constant Rose.Capabilities.Capability :=
                                  Init.Calls.Call
                                    (Create_Cap,
                                     (16#0000_000E#,
                                      16#0002_0001#,
                                      16#0000_0CF8#,
                                      16#0000_0000#));
         Data_Port_Out_Cap    : constant Rose.Capabilities.Capability :=
                                  Init.Calls.Call
                                    (Create_Cap,
                                     (16#0000_000E#,
                                      16#0002_0001#,
                                      16#0000_0CFC#,
                                      16#0000_0000#));
         Data_Port_In_Cap     : constant Rose.Capabilities.Capability :=
                                  Init.Calls.Call
                                    (Create_Cap,
                                     (16#0000_000E#,
                                      16#0002_0002#,
                                      16#0000_0CFC#,
                                      16#0000_0000#));
         PCI_Id               : constant Rose.Objects.Object_Id :=
                                  Init.Calls.Launch_Boot_Module
                                    (Boot_Cap, PCI_Module, Low_Priority,
                                     Create_Endpoint_Cap, Cap_Set_Cap,
                                     (Console_Write_Cap,
                                      Command_Port_Out_Cap,
                                      Data_Port_Out_Cap,
                                      Data_Port_In_Cap));
         Copy_PCI_Cap         : constant Rose.Capabilities.Capability :=
                                  Init.Calls.Call
                                    (Create_Cap,
                                     (9, 1,
                                      Word (PCI_Id mod 2 ** 32),
                                      Word (PCI_Id / 2 ** 32)));

      begin
         PCI_Cap :=
           Copy_Cap_From_Process (Copy_PCI_Cap, 450);
      end;

      declare
         Command_0_Cap : constant Rose.Capabilities.Capability :=
                                  Init.Calls.Call
                                    (Create_Cap,
                                     (16#0000_000E#,
                                      16#0000_0003#,
                                      16#0000_01F0#,
                                      16#0000_01F7#));
         Control_0_Cap : constant Rose.Capabilities.Capability :=
                           Init.Calls.Call
                             (Create_Cap,
                              (16#0000_000E#,
                               16#0000_0001#,
                               16#0000_03F6#,
                               16#0000_03F6#));
         Data_0_Cap_8  : constant Rose.Capabilities.Capability :=
                           Init.Calls.Call
                             (Create_Cap,
                              (16#0000_000E#,
                               16#0000_0002#,
                               16#0000_01F0#,
                               16#0000_01F7#));
         Data_0_Cap_Read_16 : constant Rose.Capabilities.Capability :=
                                Init.Calls.Call
                                  (Create_Cap,
                                   (16#0000_000E#,
                                    16#0001_0002#,
                                    16#0000_01F0#,
                                    16#0000_01F7#));
         Data_0_Cap_Write_16   : constant Rose.Capabilities.Capability :=
                                   Init.Calls.Call
                                     (Create_Cap,
                                      (16#0000_000E#,
                                       16#0001_0001#,
                                       16#0000_01F0#,
                                       16#0000_01F7#));
         Reserve_Primary_IRQ   : constant Rose.Capabilities.Capability :=
                                   Init.Calls.Call
                                     (Create_Cap,
                                      (6, 1, 46, 0));
         Reserve_Secondary_IRQ : constant Rose.Capabilities.Capability :=
                                   Init.Calls.Call
                                     (Create_Cap,
                                      (6, 1, 47, 0));
         Ata_Id                : constant Rose.Objects.Object_Id :=
                                   Init.Calls.Launch_Boot_Module
                                     (Boot_Cap, ATA_Module,
                                      Device_Driver_Priority,
                                      Create_Endpoint_Cap, Cap_Set_Cap,
                                      (Console_Write_Cap,
                                       PCI_Cap,
                                       Reserve_Primary_IRQ,
                                       Reserve_Secondary_IRQ,
                                       Command_0_Cap,
                                       Control_0_Cap,
                                       Data_0_Cap_8,
                                       Data_0_Cap_Read_16,
                                       Data_0_Cap_Write_16,
                                       Timer_Cap));
         Copy_Ata_Cap          : constant Rose.Capabilities.Capability :=
                                  Init.Calls.Call
                                    (Create_Cap,
                                     (9, 1,
                                      Word (Ata_Id mod 2 ** 32),
                                      Word (Ata_Id / 2 ** 32)));
      begin

         Hd0_Cap :=
           Copy_Cap_From_Process
             (Copy_Ata_Cap,
              Rose.Interfaces.Get_Interface_Endpoint,
              0);

         Hd1_Cap :=
           Copy_Cap_From_Process
             (Copy_Ata_Cap,
              Rose.Interfaces.Get_Interface_Endpoint,
              1);

      end;

      declare
         Store_Id : constant Rose.Objects.Object_Id :=
                      Init.Calls.Launch_Boot_Module
                        (Boot_Cap, Store_Module, Device_Driver_Priority,
                         Create_Endpoint_Cap, Cap_Set_Cap,
                         (Delete_Cap,
                          Console_Write_Cap));
         Copy_Store_Cap : constant Rose.Capabilities.Capability :=
                            Init.Calls.Call
                              (Create_Cap,
                               (9, 1,
                                Word (Store_Id mod 2 ** 32),
                                Word (Store_Id / 2 ** 32)));
      begin
         Storage_Cap :=
           Copy_Cap_From_Process
             (Copy_Store_Cap,
              Rose.Interfaces.Storage.Storage_Interface);
         Add_Storage_Cap :=
           Copy_Cap_From_Process
             (Copy_Store_Cap,
              Rose.Interfaces.Storage.Add_Backing_Store_Endpoint);
         Reserve_Storage_Cap :=
           Copy_Cap_From_Process
             (Copy_Store_Cap,
              Rose.Interfaces.Storage.Reserve_Storage_Endpoint);
      end;

      declare
         Create_Process_Cap : constant Rose.Capabilities.Capability :=
                                Init.Calls.Call
                                  (Create_Cap,
                                   (7, 4, 0, 0));
         Elf_Id       : constant Rose.Objects.Object_Id :=
                            Init.Calls.Launch_Boot_Module
                              (Boot_Cap, Elf_Module, Device_Driver_Priority,
                               Create_Endpoint_Cap, Cap_Set_Cap,
                               (Delete_Cap, Rescind_Cap,
                                Console_Write_Cap,
                                Mem_Cap, Create_Process_Cap));
         Copy_Elf_Cap : constant Rose.Capabilities.Capability :=
                            Init.Calls.Call
                              (Create_Cap,
                               (9, 1,
                                Word (Elf_Id mod 2 ** 32),
                                Word (Elf_Id / 2 ** 32)));
      begin
         Launch_Elf_Cap :=
           Copy_Cap_From_Process
             (Copy_Elf_Cap,
              Rose.Interfaces.Executable.Launch_Endpoint);
      end;

      declare
         use Rose.Interfaces.Partitions;
         Scan_Id : constant Rose.Objects.Object_Id :=
                     Init.Calls.Launch_Boot_Module
                       (Boot_Cap, Scan_Module, File_System_Priority,
                        Create_Endpoint_Cap, Cap_Set_Cap,
                        (Console_Write_Cap,
                         Hd0_Cap));
         Copy_Scan_Cap : constant Rose.Capabilities.Capability :=
                           Init.Calls.Call
                             (Create_Cap,
                              (9, 1,
                               Word (Scan_Id mod 2 ** 32),
                               Word (Scan_Id / 2 ** 32)));
         Count_Cap     : constant Rose.Capabilities.Capability :=
                           Copy_Cap_From_Process
                             (Copy_Scan_Cap, Partition_Count_Endpoint);
         Part_Cap      : constant Rose.Capabilities.Capability :=
                           Copy_Cap_From_Process
                             (Copy_Scan_Cap, Get_Partition_Endpoint);
         Parts         : Client.Partitions_Client;
      begin
         Client.Open_Cap_Set (Parts, Count_Cap, Part_Cap);

         for I in 1 .. Client.Partition_Count (Parts) loop
            Load_Partition
              (Client     => Parts,
               Device_Cap => Hd0_Cap,
               Index      => I);
         end loop;

      end;

      declare
         Install_Caps : Init.Calls.Array_Of_Capabilities (1 .. 2);
      begin
         Init.Calls.Call
           (Create_Endpoint_Cap,
            (Rose.Words.Word
                 (Rose.Interfaces.Installer.Install_Endpoint mod 2 ** 32),
             Rose.Words.Word
               (Rose.Interfaces.Installer.Install_Endpoint / 2 ** 32)),
            Install_Caps);
         Install_Receiver := Install_Caps (1);
         Install_Endpoint := Install_Caps (2);
      end;



      declare
         IsoFS_Id : constant Rose.Objects.Object_Id :=
                      Init.Calls.Launch_Boot_Module
                        (Boot_Cap, ISOFS_Module, File_System_Priority,
                         Create_Endpoint_Cap, Cap_Set_Cap,
                         (Console_Write_Cap,
                          Hd1_Cap));
         Copy_IsoFS_Cap : constant Rose.Capabilities.Capability :=
                            Init.Calls.Call
                              (Create_Cap,
                               (9, 1,
                                Word (IsoFS_Id mod 2 ** 32),
                                Word (IsoFS_Id / 2 ** 32)));
      begin
         Install_Media_FS :=
           Copy_Cap_From_Process
             (Copy_IsoFS_Cap,
              Rose.Interfaces.File_System.Root_Directory_Endpoint);
      end;

      declare
         Write_System_Image_Cap : constant Rose.Capabilities.Capability :=
                                    Init.Calls.Call
                                      (Create_Cap,
                                       (7, 2, 0, 0));

         Restore_Id : constant Rose.Objects.Object_Id :=
                        Init.Calls.Launch_Boot_Module
                          (Boot_Cap, Restore_Module, File_System_Priority,
                           Create_Endpoint_Cap, Cap_Set_Cap,
                           (Delete_Cap,
                            Console_Write_Cap,
                            Active_Swap_Cap,
                            Inactive_Swap_Cap,
                            Log_Cap,
                            Add_Storage_Cap,
                            Reserve_Storage_Cap,
                            Write_System_Image_Cap,
                            Install_Media_FS,
                            Install_Endpoint));

         pragma Unreferenced (Restore_Id);
         Params : aliased Rose.Invocation.Invocation_Record;
         Reply  : aliased Rose.Invocation.Invocation_Record;
         Exec   : Rose.Objects.Object_Id :=
                    Rose.Objects.Null_Object_Id;
         Install_Cap : Rose.Capabilities.Capability :=
                         Rose.Capabilities.Null_Capability;
         First  : Boolean := True;
      begin
         loop
            Rose.System_Calls.Initialize_Receive (Params, Install_Receiver);
            Rose.System_Calls.Receive_Caps (Params, 2);
            Rose.System_Calls.Invoke_Capability (Params);
            exit when not Params.Control.Flags (Rose.Invocation.Send_Caps);

            Rose.System_Calls.Initialize_Reply (Reply, Params.Reply_Cap);

            if First then
               Exec :=
                 Init.Installer.Install_Exec_Library
                   (Create_Cap      => Create_Cap,
                    Storage_Cap     => Storage_Cap,
                    Reserve_Cap     => Reserve_Storage_Cap,
                    Launch_Cap      => Launch_Elf_Cap,
                    Cap_Stream      => Params.Caps (0),
                    Standard_Output => Console_Write_Cap,
                    Binary_Stream   => Params.Caps (1),
                    Binary_Length   => Params.Data (0));
               declare
                  Copy_Exec_Cap : constant Rose.Capabilities.Capability :=
                                    Init.Calls.Call
                                      (Create_Cap,
                                       (9, 1,
                                        Word (Exec mod 2 ** 32),
                                        Word (Exec / 2 ** 32)));
               begin
                  Install_Cap :=
                    Copy_Cap_From_Process
                      (Copy_Exec_Cap,
                       Rose.Interfaces.Exec.Install_Endpoint);
               end;
               First := False;
            else
               declare
                  Launch : constant Rose.Capabilities.Capability :=
                             Init.Installer.Install_Executable
                               (Create_Cap    => Create_Cap,
                                Install_Cap   => Install_Cap,
                                Cap_Stream    => Params.Caps (0),
                                Binary_Stream => Params.Caps (1),
                                Binary_Length => Params.Data (0));
               begin
                  Rose.System_Calls.Send_Cap (Reply, Launch);
               end;
            end if;

            Rose.System_Calls.Invoke_Capability (Reply);
         end loop;
      end;

      Init.Calls.Send_String
        (Console_Write_Cap, "init: exiting" & NL);
      Init.Calls.Send (Exit_Cap);

   end Run_Init;

end Init.Run;
