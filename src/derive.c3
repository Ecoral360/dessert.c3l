module derive;

macro derive(...) <Type> @const @builtin {
  var $out = "";
  $for int $i = 0; $i < $vacount; $i++:
    $out +++= $eval("derive_" +++ $stringify($vaexpr[$i]))(Type);
  $endfor
  return $out;
}

macro derive_serialize($Type) @const {
  return @sprintf("fn void? %s.serialize(&self, Serializer ser) => ser::impl_serialize(self, ser);\n", $Type::name);
}
macro derive_deserialize($Type) @const {
  return @sprintf("fn void? %s.deserialize(&self, Deserializer des) => des::impl_deserialize(self, des);\n", $Type::name);
}
