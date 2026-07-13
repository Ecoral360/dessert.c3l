module derive;

macro derive(String $typename, ...) @const @builtin {
  var $out = "";
  $for int $i = 0; $i < $vaarg.len; $i++:
    $out +++= $eval($stringify($vaarg[$i]))($typename);
  $endfor
  return $out;
}

module derive::dessert;

macro serialize(String $typename) @const {
  return @sprintf("macro void? %s.serialize(&self, ser) => dessert::ser::impl_serialize{%s*, $Typeof(ser)}(self, ser);\n", $typename, $typename);
}
macro deserialize(String $typename) @const {
  return @sprintf("macro void? %s.deserialize(&self, des) => dessert::des::impl_deserialize{%s*, $Typeof(des)}(self, des);\n", $typename, $typename);
}

module derive;

macro dessert(String $typename) @const {
  return @sprintf("%s\n%s", dessert::serialize($typename), dessert::deserialize($typename));
}
