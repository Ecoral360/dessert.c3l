module example @if($feature(DESSERT_EXAMPLE));
import std;
import dessert;
import json;
import derive;
import std::collections::object;
import dessert::format::dotenv;

$expand(derive(Loglevel::name, dessert));
enum Loglevel @DEnum({ .rename_all = LOWER_CASE }) {
  VERBOSE,
  DEBUG,
  INFO,
  WARN,
  ERROR,
}

faultdef INVALID_EMAIL;

typedef Email = String;
macro void? Email.serialize(&self, ser) => ser.serialize_string((String) *self)!;
macro void? Email.deserialize(&self, des) {
  String s = des.next_string()!;
  if (!s.contains("@")) {
    return INVALID_EMAIL~;
  }
  *self = (Email) s;
}

$expand(derive(Settings::name, dessert));
struct Settings @DStruct({ .rename_all = UPPER_CASE }) {
  String api_key;
  long version;
  bool debug;
  String url;
  Loglevel log_level @DField({ .rename = "LOG" });

  Email email @DField({ .required = true });
  String other_email;
}

fn void? Settings.serialize_other_email(&self, Serializer ser) {
  ser.serialize_string(string::tformat("custom: %s", self.other_email))!;
}

fn String? Settings.deserialize_other_email(&self, Deserializer des) {
  String s = des.next_string()!;
  if (!s.contains("@")) {
    return INVALID_EMAIL~;
  }
  return s;
}


fn void main() {
  Settings settings = dotenv::tload{Settings}()!!;

  io::printn(json::tserialize(settings).to_pretty_string())!!;
}
