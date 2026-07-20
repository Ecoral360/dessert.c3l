module example @if($feature(DESSERT_EXAMPLE));
import std;
import dessert;
import json;
import derive;
import std::collections::object;
import dessert::format::dotenv;

$expand(derive(Settings::name, dessert));
struct Settings @DStruct({ .rename_all = UPPER_CASE }) {
  String api_key;
  long version;
  bool debug;
  String url;
}

fn void main() {
  Settings settings = dotenv::tload{Settings}()!!;

  io::printn(json::tserialize(settings).to_pretty_string())!!;
}
