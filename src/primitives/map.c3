module dessert::ser <Key, Value>;

import std::collections::map;

fn void? HashMap.serialize(&self, Serializer s) {
  $if @is_serializable((Value){}):
    self.@each(; key, value) {
      String key_s = string::tformat("%s", key);
      s.serialize_field_start(key_s, {})!;
      serialize_value(s, value, {})!;
      s.serialize_field_end(key_s, {})!;
    };
  $else
    abort(@sprintf("Value not serializable '%s'", Value::name));
  $endif
}
