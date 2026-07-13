module dessert::des;
import std::collections::list;
import std::collections::maybe;
import std::collections::map;
import std::collections::object;
import std::io;
import dessert::utils;


interface Deserializer {
  fn void? struct_start(String name);
  fn bool? has_next_field();
  fn String? next_field_name();
  fn String? peek_field_name();
  fn void? struct_end(String name);

  fn void? slice_start();
  fn bool? has_next_slice_item();
  fn void? slice_end();

  <*
    Returns :
    `true` if the next element is a null value and consume it. 
    `false` if the next element is not a null value and ***must not*** consume it.
  *>
  fn bool? next_null();

  fn bool? next_bool();
  fn long? next_long();
  fn String? next_string();
  fn double? next_double();

  fn Object*? next_any() @optional;

  fn void? skip_next_value() @optional;

  fn String? next_enum_description() @optional;

  fn char? next_char() @optional;
  fn ichar? next_ichar() @optional;

  fn short? next_short() @optional;
  fn int? next_int() @optional;
  fn int128? next_int128() @optional;

  fn ushort? next_ushort() @optional;
  fn uint? next_uint() @optional;
  fn ulong? next_ulong() @optional;
  fn uint128? next_uint128() @optional;

  fn ZString? next_zstring() @optional;

  fn float? next_float() @optional;

  fn Allocator get_allocator() @optional;
}

faultdef VALIDATOR_ERROR;
faultdef DUPLICATED_KEY, INVALID_ENUM_VALUE, UNKNOWN_FIELD, INLINED_UNION_BEFORE_TAG, UNMAPPED_UNION_VARIANT;
faultdef UNSUPPORTED_DATA_TYPE, UNSUPPORTED_ANY;

// Should be treated as a protocol, don't derive it directly
interface Deserializable {
  fn void? deserialize(Deserializer deserializer);
}

// macro bool @is_hashmap($Type) => $Type::qname.@starts_with("std::collections::map::HashMap");
//
// macro bool @is_list($Type) => $Type::qname.@starts_with("std::collections::list::List");

macro bool String.@starts_with($self, String $other) @const {
  return $self.len >= $other.len &&& $self[:$other.len] == $other;
}

macro @is_deserializable($Output) @const {
  $Output $value;
  return $defined($value.deserialize) ||| $Output::is_generic(HashMap) ||| ($defined($value.len) &&& $defined($value[0]) &&& @is_deserializable($Typeof($value[0]))) ||| $Output::is_generic(Maybe);
}

<*
  @require($defined(Deserializer d = deserializer))
*>
macro Output? deserialize(deserializer) <Output> => deserialize_value{Output, $Typeof(deserializer)}(deserializer, {});

<* thanks to @nonnorm for this helper macro ! *>
macro @method_fallback(des, #method, #fallback) @local {
  var $method = $stringify(#method);
  $switch:
    $case $Typeof(des) == Deserializer:
      if (&des.$method) {
        return des.$method();
      }
      return #fallback;
    $case $defined(des.$method):
      return des.$method();
    $default:
      return #fallback;
  $endswitch
}

<* thanks to @nonnorm for this helper macro ! *>
macro @method_fallback_chain(des, #method, ...) @local {
	var $method = $stringify(#method);
	$if $Typeof(des) == Deserializer:
		if (&des.$method) {
			return des.$method();
		}

		$for var $i = 0; $i < $vaarg.len; $i++:
			var $fallback = $stringify($vaarg[$i]);
			// Would prefer to use else if, but it probably doesn't matter
			if (&des.$fallback) {
				return des.$fallback();
			}
		$endfor
	$endif

	$if $defined(des.$method):
		return des.$method();
  $else
    $for var $i = 0; $i < $vaarg.len; $i++:
      var $fallback = $stringify($vaarg[$i]);
      $if $defined(des.$fallback):
        return des.$fallback();
      $endif
    $endfor
  $endif
}

fn void? impl_deserialize(Value value, Des deserializer) <Value, Des> {
  return impl_deserialize_inline(value, deserializer);
}

<*
  @require($defined(Deserializer d = deserializer))
*>
macro void? impl_deserialize_inline(value, deserializer) @local {
  $if $Typeof(value)::kind != POINTER:
    $error "The first parameter must be a &self pointer.";
  $endif

  Allocator allocator = @method_fallback(deserializer, get_allocator, tmem);

  $switch:
    $case $Typeof(value)::inner.kind == ENUM:
      var $type = $Typeof(value)::inner;
      var $enum_config = $type.has_tag("dessert:des:enum") ??? $type.get_tag("dessert:des:enum") : (DEnumConfig) {};

      $Typefrom($Typeof(value)::inner) $fallback;
      bool $found = false;
      $if $enum_config.fallback.len > 0:
        $foreach $v : $type.values:
          $if $v.description == $enum_config.fallback:
            $fallback = $v;
            $found = true;
          $endif
        $endforeach
        $if !$found:
          $error @sprintf("The fallback of an enum must be a valid member of that enum ('%s' is not a member of %s)", $enum_config.fallback, $type.name);
        $endif
        *value = $fallback;
      $endif

      $switch $enum_config.as:
        $case DESCRIPTION:
          String name = @method_fallback(deserializer, next_enum_description, deserializer.next_string())!;
          int found = -1;
          foreach(i, v : $type.names) {
            if (v == name) {
              found = (int) i;
              break;
            }
          }

          if (found == -1) {
            $if $enum_config.fallback.len > 0:
              return;
            $else
              return INVALID_ENUM_VALUE~;
            $endif
          }
          *value = $type.values[found];

        $case ORDINAL:
          $Typefrom($type.inner) ordinal = deserialize{$type.inner}(deserializer)!;
          *value = $type.from_ordinal(ordinal);

        $case FIELD:
          String $field_name = $enum_config.field;
          $if $field_name.len == 0:
            $error "When the 'enum_as' attribute is set to 'FIELD', 'enum_field' must be provided with the name of an associated field of the enum.";
          $endif
          $foreach $member : $type.members:
            $if $member.name == $field_name:
              $Typefrom($member.type) field_value = deserialize{$member.type}(deserializer)!;
              $if $enum_config.fallback.len > 0:
                if (try v = $type.lookup_field($field_name, field_value)) {
                  *value = v;
                }
              $else
                *value =  $type.lookup_field($field_name, field_value)!;
              $endif
            $endif
          $endforeach
      $endswitch

    $case $Typeof(value)::inner.kind == UNION:
    $case $Typeof(value)::inner.kind == STRUCT:
      var $type = $Typeof(value)::inner;
      var $struct_config = $type.has_tag("dessert:des:struct") ??? $type.get_tag("dessert:des:struct") : (DStructConfig) {};
      List{String} names;
      names.tinit();
      defer names.free();

      while(deserializer.has_next_field()!) {
        String? next_key = deserializer.peek_field_name();
        defer (void) alloc::free(allocator, next_key);
        if (catch next_key) {
          io::eprintfn("Error deserializing after deserializing: %s", names);
          next_key!;
          return;
        }
        $if $struct_config.deny_dup_keys:
          if (names.contains(next_key)) {
            return DUPLICATED_KEY~;
          }
        $endif

        $foreach $member : $Typeof(value)::inner.members:
          if (@des_field(deserializer, value, $member, next_key, names, $struct_config, allocator)!) {
            names.push($member.name);
            continue;
          }
        $endforeach

        $if $struct_config.deny_unknown_fields:
          io::eprintfn("While deserializing '" +++ $Typeof(value)::inner.name +++ "' (which denies unknown fields), encountered unknown field '%s'.", next_key);
          return UNKNOWN_FIELD~;
        $else
          // Skip the value if not found
          (void) deserializer.next_field_name()!;
          @method_fallback(deserializer, skip_next_value, @skip_next_value_fallback(deserializer))!;
        $endif
      }
  $endswitch
}

macro void? @skip_next_value_fallback(deserializer) @local {
  Object* o = deserialize{Object*}(deserializer)!;
  if (o) o.free(); // we must free the Object* allocated
}

macro bool? @des_field(deserializer, value, $member, next_key, List{String} names, DStructConfig $struct_config, allocator) @local {
  DFieldConfig $config = $member.has_tag("dessert:des:field") ??? $member.get_tag("dessert:des:field") : (DFieldConfig) {};
  var $name = utils::@rename($config, $member.name, $struct_config);

  $if $member.type.name == @sprintf("%s.$anon", $Typeof(value)::inner.name):
    $foreach $m : $member.type.members:
      if (@des_field(deserializer, &value.$member, $m, next_key, {}, $member.has_tag("dessert:des:struct") ??? $type.get_tag("dessert:des:struct") : $struct_config, allocator)!) return true;
    $endforeach
  $endif

  $if $config.flatten &&& !$member.type.is_generic(List) &&& !($member.type.kind == POINTER &&& $member.type.inner.is_generic(List)):
    value.$member = deserialize_value{$member.type, $Typeof(deserializer)}(deserializer, $config)!;
    return true;
  $else 
    if ($name == next_key) {
      $if !$config.skip:
        $switch:
          $case $member.type.kind == UNION &&& $config.tagged.inlined:
            $if $config.tagged.by.len == 0:
              $error @sprintf("Inlined unions MUST have a 'tagged_by' value for deserialization (%s)", $member.name);
            $endif

            if (!names.contains($config.tagged.by)) {
              io::eprintfn("While deserializing '" +++ $Typeof(value)::inner.name +++ "', encountered inlined union field '%s' before tag key '%s'.", next_key, $config.tagged.by);
              return INLINED_UNION_BEFORE_TAG~;
            }

            var tag_value = value.$eval($config.tagged.by);
            var next_value = value.$member;

            var $the_switch = "";
            var $UType = $member.type;

            $switch:
              $case $config.tagged.match.by == ORDINAL ||| $Typeof(tag_value)::kind != ENUM:
                $the_switch = "switch ((sz) tag_value) {";
                $foreach $i, $m : $UType::members:
                  $the_switch +++= @sprintf("case %s:\n", $i);
                  $the_switch +++= @sprintf("@des_field(deserializer, &next_value, $UType::members[%s], $UType::members[%s].name, {}, {}, allocator)!;\n", $i, $i);
                $endforeach
                $the_switch +++= @default_unmapped($config);
                $the_switch +++= "}";

              $case $config.tagged.match.by == DESCRIPTION:
                $the_switch = "switch (tag_value) {";
                $foreach $i, $m : $UType::members:
                  $the_switch +++= @sprintf("case %s:\n", @str_upper($m.name));
                  $the_switch +++= @sprintf("@des_field(deserializer, &next_value, $UType::members[%s], $UType::members[%s].name, {}, {}, allocator)!;\n", $i, $i);
                $endforeach
                $the_switch +++= @default_unmapped($config);
                $the_switch +++= "}";

              $case $config.tagged.match.by == FIELD:
                var $field_name = $config.tagged.match.field;
                $if $field_name.len == 0:
                  $error "While serializing a tagged union: When the 'tagged.match_by' attribute is set to 'FIELD', 'field' must be provided with the name of an associated field of the enum.";
                $endif

                $if !$defined(tag_value.$field_name):
                  $error @sprintf("Enum %s doesn't have field '%s'", $Typeof(tag_value)::name, $field_name);
                $endif

                $if $Typeof(tag_value.$field_name) != String:
                  $error @sprintf("To be used as a union variant matcher, the field must be an string (was '%s')", $field_name);
                $endif

                $the_switch = @sprintf("switch (tag_value.%s) {", $field_name);
                $foreach $i, $m : $UType::members:
                  $the_switch +++= @sprintf("case \"%s\":\n", $m.name);
                  $the_switch +++= @sprintf("@des_field(deserializer, &next_value, $UType::members[%s], $UType::members[%s].name, {}, {}, allocator)!;\n", $i, $i);
                $endforeach
                $the_switch +++= @default_unmapped($config);

                $the_switch +++= "}";

            $endswitch

            $expand($the_switch);

            value.$member = next_value;

          $case $member.type.kind == UNION &&& !$config.tagged.inlined:
          $case $member.type.name == @sprintf("%s.%s", $Typeof(value)::inner.name, $member.name):
          $case $member.type.name == @sprintf("%s.$anon", $Typeof(value)::inner.name):
            (void) deserializer.next_field_name()!;
            deserializer.struct_start($member.type.name)!;
            impl_deserialize_inline(&value.$member, deserializer)!;
            deserializer.struct_end($member.type.name)!;

          $case $member.type.is_generic(List) &&& $config.flatten:
            (void) deserializer.next_field_name()!;

            $Typefrom($member.type.generic_args[0])? next_value = deserialize_value{$member.type.generic_args[0], $Typeof(deserializer)}(deserializer, $config);
            if (catch e = next_value) {
              io::eprintfn("Error [%s] deserializing key: '%s' (%s)", e, next_key, $member.type.name);
              next_value!;
              return false;
            }

            if (!value.$member.is_initialized()) value.$member.init(allocator);
            value.$member.push(next_value);

          $case $member.type.kind == POINTER &&& $member.type.inner.is_generic(List) &&& $config.flatten:
            (void) deserializer.next_field_name()!;

            $Typefrom($member.type.inner.generic_args[0])? next_value = deserialize_value{$member.type.inner.generic_args[0], $Typeof(deserializer)}(deserializer, $config);
            if (catch e = next_value) {
              io::eprintfn("Error [%s] deserializing key: '%s' (%s)", e, next_key, $member.type.name);
              next_value!;
              return false;
            }

            if (value.$member == null) {
              value.$member = alloc::alloc(allocator, $member.type.inner);
              value.$member.init(allocator);
            }
            value.$member.push(next_value);

          $default:
            (void) deserializer.next_field_name()!;

            $Typefrom($member.type)? next_value = deserialize_value{$member.type, $Typeof(deserializer)}(deserializer, $config);
            if (catch e = next_value) {
              io::eprintfn("Error [%s] deserializing key: '%s' (%s)", e, next_key, $member.type.name);
              next_value!;
              return false;
            }

            value.$member = next_value;

        $endswitch
      $else
        // skip the key
        (void) deserializer.next_field_name()!;
      $endif
      return true;
    }

    return false;
  $endif
}

macro @default_unmapped(DFieldConfig $config) @local @const {
  $switch $config.tagged.unmapped.as:
    $case ERROR:
      return "default: return UNMAPPED_UNION_VARIANT~;";
    $case EMPTY_STRUCT:
      return "default: (void) deserializer.next_field_name()!; (void) deserialize_value{Object*, $Typeof(deserializer)}(deserializer, {})!;";
    $case NULL:
      return "default: (void) deserializer.next_field_name()!; (void) deserialize_value{Maybe{int}, $Typeof(deserializer)}(deserializer, {})!;";
    $case ZERO:
      return "default: (void) deserializer.next_field_name()!; (void) deserialize_value{int, $Typeof(deserializer)}(deserializer, {})!;";
  $endswitch
}

fn Output? deserialize_value(Des deserializer, DFieldConfig config) <Output, Des> {
  Output value;
  $switch:
    $case Output::kind == POINTER:
      if (deserializer.next_null()!) {
        return null;
      } else {
        $switch:
          $case Output == Object*:
            return @method_fallback(deserializer, next_any, UNSUPPORTED_ANY~)!;

          $case Output::inner.is_generic(List):
            Allocator allocator = @method_fallback(deserializer, get_allocator, tmem);

            value = alloc::alloc(allocator, Output::inner);
            value.init(allocator);

            deserializer.slice_start()!;
            while(deserializer.has_next_slice_item()!) {
              value.push(deserialize{Output::inner.generic_args[0]}(deserializer)!);
            }
            deserializer.slice_end()!;
            return value;

          $default:
            Allocator allocator = @method_fallback(deserializer, get_allocator, tmem);

            value = alloc::new(allocator, Output::inner);
            *value = deserialize_value{Output::inner, Des}(deserializer, config)!;
            return value;
        $endswitch
      }

    $case Output == Object:
      $error "Cannot deserialize to `Object`, only to `Object*`";

    $case Output::kind == CONSTDEF:
      value = (Output) deserialize{Output::inner}(deserializer)!;
      return value;

    $case $defined(value.deserialize) &&& $defined(value.deserialize(deserializer)):
      $if Output != Object &&& Output::kind == STRUCT:
        if (!config.flatten) deserializer.struct_start(Output::name)!;
      $endif
      value.deserialize(deserializer)!;
      $if Output != Object &&& Output::kind == STRUCT:
        if (!config.flatten) deserializer.struct_end(Output::name)!;
      $endif
      return value;

    $case Output::is_generic(HashMap):
      Allocator allocator = @method_fallback(deserializer, get_allocator, tmem);

      $if $Typeof(value.tkeys()[0]) != String:
        $error "Only a hashmap with string key can be deserialized";
      $endif

      value.init(allocator);

      if (!config.flatten) deserializer.struct_start(Output::name)!;
      while(deserializer.has_next_field()!) {
        String next_key = deserializer.next_field_name()!;
        value.set(next_key, deserialize{$Typeof(value.tvalues()[0])}(deserializer)!);
      }
      if (!config.flatten) deserializer.struct_end(Output::name)!;
      return value;

    $case Output::is_generic(List):
      Allocator allocator = @method_fallback(deserializer, get_allocator, tmem);

      value.init(allocator);

      deserializer.slice_start()!;
      while(deserializer.has_next_slice_item()!) {
        value.push(deserialize{Output::generic_args[0]}(deserializer)!);
      }
      deserializer.slice_end()!;
      return value;

    $case Output::is_generic(Maybe):
      if (deserializer.next_null()!) {
        return (Maybe{$Typeof(value.value)}) {};
      } else {
        return maybe::value{$Typeof(value.value)}(deserialize_value{$Typeof(value.value), Des}(deserializer, config)!);
      }

    $case $defined(value.len) &&& $defined(value[0]) &&& Output != String:
      Allocator allocator = @method_fallback(deserializer, get_allocator, tmem);

      List{Output::inner} elements;
      deserializer.slice_start()!;
      while(deserializer.has_next_slice_item()!) {
        elements.push(deserialize{Output::inner}(deserializer)!);
      }
      deserializer.slice_end()!;
      return elements.to_array(allocator);

    $default:
      return @deserialize_primitive_value(Output, deserializer)!;

  $endswitch
}


macro @deserialize_primitive_value($Type, des) @local {
  $switch $Type:
    $case String:
      return des.next_string()!;

    $case char:
      return @method_fallback(des, next_char, des.next_string()[0])!;

    $case bool:
      return des.next_bool()!;

    $case ichar:
      return (ichar) @method_fallback(des, next_ichar, des.next_long())!;

    $case short:
      return (short) @method_fallback(des, next_short, des.next_long())!;

    $case int:
      return (int) @method_fallback(des, next_int, des.next_long())!;

    $case long:
      return des.next_long()!;

    $case int128:
      return @method_fallback(des, next_int128, UNSUPPORTED_DATATYPE~)!;

    $case ushort:
      return (ushort) @method_fallback_chain(des, next_ushort, next_ulong, next_long)!;

    $case uint:
      return (uint) @method_fallback_chain(des, next_uint, next_ulong, next_long)!;

    $case ulong:
      return (ulong) @method_fallback(des, next_ulong, des.next_long())!;

    $case uint128:
      return @method_fallback(des, next_uint128, UNSUPPORTED_DATATYPE~)!;

    $case float:
      return (float) @method_fallback(des, next_float, des.next_double())!;

    $case double:
      return des.next_double()!;

    $default:
      $error "The value cannot be deserialize: " +++ $Type::name;
  $endswitch
}
