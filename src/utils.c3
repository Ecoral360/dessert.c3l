module dessert::utils;

import std::collections::maybe;

macro @is_maybe($value) @const {
   return $Typeof($value)::is_generic(Maybe);
}

macro @is_maybe_expr(#value) {
  return $Typeof(#value)::is_generic(Maybe);
}

macro @is_maybe_type($Type) @const {
  return $Type::is_generic(Maybe);
}

macro @get_maybe_inner_type($Type) {
  $if @is_maybe_type($Type):
    return @get_maybe_inner_type($Type::generic_args[0]);
  $endif
  return $Type;
}

macro @get_tag($Type, String $tag_name, $default_val) @const @builtin => $Type::has_tag($tag_name) ??? $Type::get_tag($tag_name) : $default_val;

macro @rename(DFieldConfig $config, String $name, DStructConfig $struct_config) @const {
  $if $config.rename.len > 0:
    return $config.rename;
  $else
    $switch $struct_config.rename_all:
      $case VERBATIM:
        return $name;

      $case CAMEL_CASE:
        return @str_camelcase($name);

      $case PASCAL_CASE:
        return @str_pascalcase($name);

      $case SNAKE_CASE:
        return @str_snakecase($name);

      $case CONSTANT_CASE:
        return @str_constantcase($name);

      $case LOWER_CASE:
        return @str_lower($name);

      $case UPPER_CASE:
        return @str_upper($name);

      $case KEBAB_CASE:
        return @str_replace(@str_snakecase($name), "_", "-");

      $default:
        $error @sprintf("CaseConvention %s not supported for now.");
    $endswitch
  $endif
}

