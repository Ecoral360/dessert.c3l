module dessert::ser;
import std::core::types;
import dessert::json;
import std::io;
import std::collections::maybe;

interface Serializer {
  fn void? serialize_bool(bool b);
  fn void? serialize_char(char b);
  fn void? serialize_int(int b);
  fn void? serialize_string(String s);

  fn void? serialize_null();
  // fn void? serialize_slice(Serializable[] values);

  fn void? serialize_slice_start();
  fn void? serialize_slice_end(ulong len);

  // fn Output? serialize_short(short b);
  // fn Output? serialize_usz(usz b);
  // fn Output? serialize_long(long b);

  fn void? serialize_field_start(String name);
  fn void? serialize_field_end();

  fn void? struct_start();
  fn void? struct_end();
}

faultdef VALIDATOR_ERROR;

interface Serializable {
  fn void? serialize(Serializer serializer);
}

fn void? String.serialize(&self, Serializer ser) @dynamic {
  return ser.serialize_string(*self);
}
fn void? int.serialize(&self, Serializer ser) @dynamic {
  return ser.serialize_int(*self);
}
fn void? bool.serialize(&self, Serializer ser) @dynamic {
  return ser.serialize_bool(*self);
}

fn void? Maybe{Serializable}.serialize(&self, Serializer ser) @dynamic {
  if (catch self.get()) {
    return ser.serialize_null();
  } else {
    return self.value.serialize(ser);
  }
}

macro serialize(serializer, value) {
  value.serialize(serializer)!;
  return serializer.result();
}

/*
  attributes:
  - rename
  - skip
  - aliases
  - default
  - validator
*/

macro impl_serialize(serializer, s) {
  serializer.struct_start()!;
  $foreach $member : $typeof(s).inner.membersof:
    var $dessert = $member.has_tagof("dessert") ??? $member.tagof("dessert") : (Dessert) {};
    $if $typeof($dessert) != Dessert:
      $error("Dessert tag value must be of type Dessert");
    $endif
    $if !$dessert.skip:
      $if $dessert.validator.len > 0: 
        if (!s.$eval($dessert.validator)(s.$eval($member.nameof))) {
          return VALIDATOR_ERROR~;
        }
      $endif
      serializer.serialize_field_start(
        $dessert.rename.len > 0 ??? $dessert.rename : $member.nameof
      )!;
      serialize_value(serializer, s.$eval($member.nameof), $member.nameof)!;
      serializer.serialize_field_end()!;
    $endif
  $endforeach
  serializer.struct_end()!;
}

macro serialize_value(serializer, value, $field_name) {
  $switch:
    $case $defined(value.value) &&& $defined(value == maybe::value{$typeof(value.value)}(value.value)):
      var inner = value.get();
      if (catch inner) {
        serializer.serialize_null()!;
      } else {
        inner.serialize(serializer)!;
      }

    $case $typeof(value).kindof == ARRAY:
    $case $typeof(value).kindof == SLICE:
      serializer.serialize_slice_start()!;
      foreach (el: value) {
        el.serialize(serializer)!;
      }
      serializer.serialize_slice_end(value.len)!;
    $case $defined(value.serialize):
      value.serialize(serializer)!;
    $default:
      $error("Field not serializable");
  $endswitch
}

// macro @serialize(#serializer, #value) {
//   var serializer = #serializer;
//   var value = #value;
//
//   $switch:
//     $case $typeof(value).kindof == STRUCT:
//       return @serialize_struct(serializer, value);
//     $case $typeof(value).kindof == ARRAY:
//     $case $typeof(value).kindof == SLICE:
//       return @serialize_slice(serializer, value);
//     $case $typeof(value).kindof == POINTER:
//       if (value == null) {
//         return serializer.serialize_null();
//       } else {
//         return @serialize(serializer, *value);
//       }
//     $case $typeof(value).kindof == SIGNED_INT:
//       return serializer.serialize_int(value);
//     $case types::is_same($typeof(value), String):
//       return serializer.serialize_string(value);
//     $default:
//       return NOT_FOUND~;
//   $endswitch
// }
//
// macro @serialize_slice(serializer, #value) {
//   serializer.serialize_slice_start()!;
//   foreach (i, member : #value) {
//     serializer.@serialize_slice_item(member)!;
//   }
//   return serializer.serialize_slice_end();
// }
//
// macro @serialize_struct(serializer, value) {
//   serializer.serialize_struct_start()!;
//   $foreach $member : $typeof(value).membersof:
//     serializer.@serialize_field($member.nameof, &value.$eval($member.nameof))!;
//   $endforeach
//   return serializer.serialize_struct_end();
// }
