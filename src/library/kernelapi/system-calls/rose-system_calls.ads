with System;

with System.Storage_Elements;

with Rose.Capabilities;
with Rose.Invocation;
with Rose.Words;

package Rose.System_Calls is

   type Sent_Words_Array is array (Positive range <>) of Rose.Words.Word;
   No_Sent_Words : Sent_Words_Array (1 .. 0);

   type Sent_Caps_Array is
     array (Positive range <>) of Rose.Capabilities.Capability;
   No_Sent_Caps : Sent_Caps_Array (1 .. 0);

   type Invocation_Flag_Array is
     array (Positive range <>) of Rose.Invocation.Invocation_Flag;

   procedure Invoke_Capability
     (Item : aliased in out Rose.Invocation.Invocation_Record);

   procedure Invoke
     (Cap       : Rose.Capabilities.Capability;
      Flags     : Invocation_Flag_Array;
      In_Words  : Sent_Words_Array;
      In_Caps   : Sent_Caps_Array;
      Out_Words : out Sent_Words_Array;
      Out_Caps  : out Sent_Caps_Array);

   procedure Invoke_Blocking_Send
     (Cap       : Rose.Capabilities.Capability;
      In_Words  : Sent_Words_Array;
      In_Caps   : Sent_Caps_Array;
      Out_Words : out Sent_Words_Array;
      Out_Caps  : out Sent_Caps_Array);

   procedure Invoke_Reply
     (Cap       : Rose.Capabilities.Capability;
      In_Words  : Sent_Words_Array;
      In_Caps   : Sent_Caps_Array;
      Out_Words : out Sent_Words_Array;
      Out_Caps  : out Sent_Caps_Array);

   procedure Send_Text
     (Params : in out Rose.Invocation.Invocation_Record;
      Text   : String);

   procedure Send_Storage_Array
     (Params   : in out Rose.Invocation.Invocation_Record;
      Storage  : System.Storage_Elements.Storage_Array;
      Writable : Boolean);

   procedure Send_Word
     (Params : in out Rose.Invocation.Invocation_Record;
      Value  : Integer);

    procedure Send_Cap
      (Params : in out Rose.Invocation.Invocation_Record;
       Cap    : Rose.Capabilities.Capability);

   procedure Send_Buffer
      (Params   : in out Rose.Invocation.Invocation_Record;
       Bytes    : System.Storage_Elements.Storage_Count;
       Buffer   : System.Address;
       Writable : Boolean);

--     procedure Receive_Buffer
--       (Params   : in out Rose.Invocation.Invocation_Record;
--        Buffer   : System.Address;
--        Writable : Boolean);

   procedure Receive_Buffer
     (Params   : in out Rose.Invocation.Invocation_Record);

   procedure Copy_Buffer
     (Params    : Rose.Invocation.Invocation_Record;
      Max_Bytes : System.Storage_Elements.Storage_Count;
      To        : System.Address);

   procedure Copy_Storage_Array
     (Params    : Rose.Invocation.Invocation_Record;
      To        : out System.Storage_Elements.Storage_Array;
      Last      : out System.Storage_Elements.Storage_Count);

    procedure Copy_Text
      (Params   : Rose.Invocation.Invocation_Record;
       To       : out String;
       Last     : out Natural);

   procedure Initialize_Send
     (Params : in out Rose.Invocation.Invocation_Record;
      Cap    : Rose.Capabilities.Capability);

   procedure Send_Word
     (Params : in out Rose.Invocation.Invocation_Record;
      Value  : Rose.Words.Word);

   procedure Receive_Words
     (Params : in out Rose.Invocation.Invocation_Record;
      Count  : Natural);

   procedure Receive_Caps
     (Params : in out Rose.Invocation.Invocation_Record;
      Count  : Natural);

end Rose.System_Calls;