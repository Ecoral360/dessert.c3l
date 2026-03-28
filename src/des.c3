module dessert::des;
import std::collections::list;
import std::collections::maybe;
import std::io;


interface Deserializer {
  fn void? struct_start();
  fn bool? has_next_field();
  fn String? next_field_name();
  fn void? struct_end();

  fn void? slice_start();
  fn bool? has_next_slice_item();
  fn void? slice_end();

  fn String? next_string();
  fn int? next_int();
  fn double? next_double();
  fn bool? next_bool();
  fn bool? next_null();
}

faultdef VALIDATOR_ERROR;
faultdef DUPLICATED_KEY;

interface Deserializable {
  fn void? deserialize(Deserializer deserializer);
}

fn void? String.deserialize(&self, Deserializer ser) @dynamic {
  *self = ser.next_string()!;
}
fn void? int.deserialize(&self, Deserializer ser) @dynamic {
  *self = ser.next_int()!;
}
fn void? bool.deserialize(&self, Deserializer ser) @dynamic {
  *self = ser.next_bool()!;
}

macro deserialize(deserializer) <Output> {
  Output value;
  $switch:
    $case $defined(value.value) &&& $defined(value == maybe::value{$typeof(value.value)}(value.value)):
      if (deserializer.next_null()!) {
        return (Maybe{$typeof(value.value)}){};
      } else {
        return maybe::value{$typeof(value.value)}(deserialize{$typeof(value.value)}(deserializer)!);
      }

    $case Output.kindof == POINTER:
      return &&deserialize{Output.inner}(deserializer);

    $case Output.kindof == ARRAY:
    $case Output.kindof == SLICE:
      List{Output.inner} elements;
      deserializer.slice_start()!;
      while(deserializer.has_next_slice_item()!) {
        elements.push(deserialize{Output.inner}(deserializer)!);
      }
      deserializer.slice_end()!;
      return elements.to_array(mem);
    $default:
      value.deserialize(deserializer)!;
      return value;
  $endswitch
}

macro impl_deserialize(deserializer, value) {
  List{String} names;
  names.init(mem);
  defer names.free();

  deserializer.struct_start()!;
  while(deserializer.has_next_field()!) {
    String next_key = deserializer.next_field_name()!;
    $foreach $member : $typeof(value).inner.membersof:
      var $dessert = $member.has_tagof("dessert") ??? $member.tagof("dessert") : (Dessert) {};
      $if $typeof($dessert) != Dessert:
        $error("Dessert tag value must be of type Dessert");
      $endif

      var $name = $dessert.rename.len > 0 ??? $dessert.rename : $member.nameof;
      if ($name == next_key) {
        if (names.contains(next_key)) {
          return DUPLICATED_KEY~;
        }
        value.$eval($member.nameof) = deserialize{$member.typeid}(deserializer)!;

        names.push($member.nameof);
      }
    $endforeach
  }
  deserializer.struct_end()!;
}
