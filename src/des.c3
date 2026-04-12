module dessert::des;
import std::collections::list;
import std::collections::maybe;
import std::collections::object;
import std::io;


interface Deserializer {
  fn void? struct_start();
  fn bool? has_next_field();
  fn String? next_field_name();
  fn void? struct_end();

  fn void? slice_start();
  fn bool? has_next_slice_item();
  fn void? slice_end();

  fn bool? next_bool();
  fn bool? next_null();

  fn Object*? next_any() @optional;

  fn char? next_char();
  fn ichar? next_ichar() @optional;

  fn short? next_short() @optional;
  fn int? next_int() @optional;
  fn long? next_long();
  fn int128? next_int128() @optional;

  fn uint? next_uint() @optional;
  fn ushort? next_ushort() @optional;
  fn ulong? next_ulong();
  fn uint128? next_uint128() @optional;

  fn String? next_string();
  fn ZString? next_zstring() @optional;

  fn float? next_float() @optional;
  fn double? next_double();
}

faultdef VALIDATOR_ERROR;
faultdef DUPLICATED_KEY, INVALID_ENUM_VALUE, UNKNOWN_FIELD;

// Should be treated as a protocol, don't derive it directly
interface Deserializable {
  fn void? deserialize(Deserializer deserializer);
}

macro @is_deserializable($Output) {
  $Output $value;
  return $defined($value.deserialize) ||| ($defined($value.len) &&& $defined($value[0])) ||| 
    ($defined($value.get) &&& $defined($value.get()) &&& 
     ($defined($value.get()!) ||| $defined($value == maybe::value{$typeof($value.value)}($value.value))));
}

macro deserialize(Deserializer deserializer) <Output> {
  Output value;
  $switch:
    $case Output.kindof == POINTER:
      if (deserializer.next_null()!) {
        return null;
      } else {
        Output v = mem::new(Output.inner);
        *v = deserialize{Output.inner}(deserializer)!;
        return v;
      }

    $case $defined(value.deserialize) &&& $defined(value.deserialize(deserializer)):
      value.deserialize(deserializer)!;
      return value;

    $case ($defined(value.get) &&& $defined(value.get()) &&& 
           ($defined(value.get()!) ||| $defined(value == maybe::value{$typeof(value.value)}(value.value)))):
      if (deserializer.next_null()!) {
        return (Maybe{$typeof(value.value)}) {};
      } else {
        return maybe::value{$typeof(value.value)}(deserialize{$typeof(value.value)}(deserializer)!);
      }

    $case $defined(value.len) &&& $defined(value[0]):
      List{Output.inner} elements;
      deserializer.slice_start()!;
      while(deserializer.has_next_slice_item()!) {
        elements.push(deserialize{Output.inner}(deserializer)!);
      }
      deserializer.slice_end()!;
      return elements.to_array(mem);

    $default:
      $error "The value cannot be deserialize: " +++ $typeof(value).nameof;

  $endswitch
}

macro impl_deserialize(value, Deserializer deserializer) {
  $if $typeof(value).kindof != POINTER:
    $error "The first parameter must be a &self pointer.";
  $endif

  $switch:
    $case $typeof(value).inner.kindof == ENUM:
      var $type = $typeof(value).inner;
      var $config = $type.has_tagof("dessert:des:enum") ??? $type.tagof("dessert:des:enum") : (DessertEnumConfig) {};

      $switch $config.as:
        $case NAME:
          String name = deserializer.next_string()!;
          int found = -1;
          foreach(i, v : $type.names) {
            if (v == name) {
              found = (int) i;
              break;
            }
          }

          if (found == -1) return INVALID_ENUM_VALUE~;
          *value = $type.values[found];

        $case ORDINAL:
          var ordinal = deserialize{$type.inner}(deserializer)!;
          *value = $type.from_ordinal(ordinal);

        $case FIELD:
          var $field_name = $config.field;
          $if $field_name.len == 0:
            $error "When the 'enum_as' attribute is set to 'FIELD', 'enum_field' must be provided with the name of an associated field of the enum.";
          $endif
          $foreach $member : $type.membersof:
            $if $member.nameof == $field_name:
              var field_value = deserialize{$member.type}(deserializer)!;
              *value = $type.lookup_field($eval($field_name), field_value)!;
            $endif
          $endforeach
      $endswitch

    $case $typeof(value).inner.kindof == STRUCT:
      var $type = $typeof(value).inner;
      var $config = $type.has_tagof("dessert:des:struct") ??? $type.tagof("dessert:des:struct") : (DessertStructConfig) {};
      List{String} names;
      names.init(mem);
      defer names.free();

      deserializer.struct_start()!;
      while(deserializer.has_next_field()!) {
        String? next_key = deserializer.next_field_name();
        if (catch next_key) {
          io::eprintfn("Error deserializing after deserializing: %s", names);
          next_key!;
          return;
        }
        $foreach $member : $typeof(value).inner.membersof:
          var $dessert = $member.has_tagof("dessert:des") ??? $member.tagof("dessert:des") : (Dessert) {};
          $if $typeof($dessert) != Dessert:
            $error("Dessert tag value must be of type Dessert");
          $endif
          var $name = $dessert.rename.len > 0 ??? $dessert.rename : $member.nameof;
          if ($name == next_key) {
            if (names.contains(next_key)) {
              return DUPLICATED_KEY~;
            }
            $typefrom($member.typeid)? next_value = deserialize{$member.typeid}(deserializer);
            if (catch next_value) {
              io::eprintfn("Error deserializing key: %s", next_key);
              next_value!;
              return;
            }
            $if !$dessert.skip:
              value.$eval($member.nameof) = next_value;
            $endif

            names.push($member.nameof);
            continue;
          }
        $endforeach
        $if $config.deny_unknown_fields:
          io::eprintfn("While deserializing '" +++ $typeof(value).inner.nameof +++ "' (which denies unknown fields), encountered unknown field '%s'.", next_key);
          return UNKNOWN_FIELD~;
        $else
          // Skip the value if not found
          (void) deserialize{Object*}(deserializer)!;
        $endif
      }
      deserializer.struct_end()!;
  $endswitch
}
