module dessert::values;

import dessert::ser;
import dessert::des;

faultdef OUTSIDE_RANGE;

typedef Email = String;
macro void? Email.serialize(&self, ser) => ser.serialize_string((String) *self)!;
macro void? Email.deserialize(&self, des) {
  String s = des.next_string()!;
  if (!s.contains("@")) {
    return INVALID_EMAIL~;
  }
  *self = (Email) s;
}

typedef Validated<Type> = Type;
macro void? Validated.serialize(&self, ser) => ser::serialize_value(ser, (Type) *self, {})!;
macro void? Validated.deserialize(&self, des, DFieldConfig $config) {
  Type s = des::deserialize{Type}(des)!;
  var $fmt = $config.fmt;
}


typedef Number<Backing, MIN, MAX> = Backing;
alias NumberLt<Backing, MAX> = Number{Backing, Backing::min, MAX};
alias NumberGt<Backing, MIN> = Number{Backing, MIN, Backing::max};

macro void? Number.serialize(&self, ser) => ser::serialize_value(ser, (Backing) *self, {})!;
macro void? Number.deserialize(&self, des) {
  Backing s = des::deserialize{Backing}(des)!;
  if (s > MAX || s < MIN) return OUTSIDE_RANGE~;
  *self = ($Typeof(*self)) s;
}
