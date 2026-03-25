module json;
import std::collections::map;
import std::collections::list;
import std::io;

enum JsonValueKind {
  INT,
  FLOAT,
  BOOL,
  STRING,
  DICT,
  ARRAY,
  NULL,
}

struct JsonValue {
  union value {
    int i;
    float f;
    bool b;
    String s;
    HashMap{String, JsonValue} d;
    List{JsonValue} l;
  }

  JsonValueKind kind;
}

fn void? JsonValue.print(self) {
  switch(self.kind) {
    case NULL:
      io::print("null");
    case INT:
      io::printf("%s", self.value.i);
    case FLOAT:
      io::printf("%s", self.value.f);
    case BOOL:
      io::printf("%s", self.value.b);
    case STRING:
      io::printf("\"%s\"", self.value.s);
    case ARRAY:
      io::printf("[");
      ulong l_len = self.value.l.len();
      foreach (i, item : self.value.l) {
        item.print()!;
        if (i < l_len - 1) {
          io::print(", ");
        }
      }
     io::printf("]");
    case DICT:
      io::printf("{");
      ulong d_len = self.value.d.len();
      
      foreach (i, entry : self.value.d.iter()) {
        io::printf("\"%s\": ", entry.key);
        entry.value.print()!;
        if (i < d_len - 1) {
          io::print(", ");
        }
      };
      io::printf("}");

    default:
      return NOT_FOUND~;
  }
}

module dessert::json;
import dessert::ser;
import json;
import std::collections::maybe;
import std::collections::list;
import std::collections::map;
import std::io;

faultdef INVALID_JSON_TYPE;

struct JsonSerializer (Serializer) {
  List{JsonValue} output;
  Maybe{String} key;
  Maybe{JsonValue} obj;
}

fn JsonSerializer new_json_serializer() {
  List{JsonValue} output;
  output.init(mem);
  return { .output = output };
}

fn void? JsonSerializer.serialize_null(&self) @dynamic {
  self.output.push({ .kind = JsonValueKind.NULL, .value = { .i = 0 } });
}

fn void? JsonSerializer.serialize_bool(&self, bool b) @dynamic {
  self.output.push({ .kind = JsonValueKind.BOOL, .value = { .b = b } });
}

fn void? JsonSerializer.serialize_char(&self, char c) @dynamic {
  self.output.push({ .kind = JsonValueKind.STRING, .value = { .s = {c} } });
}

fn void? JsonSerializer.serialize_int(&self, int i) @dynamic {
  self.output.push({ .kind = JsonValueKind.INT, .value = { .i = i } });
}

fn void? JsonSerializer.serialize_string(&self, String s) @dynamic {
  self.output.push({ .kind = JsonValueKind.STRING, .value = { .s = s } });
}

fn void? JsonSerializer.struct_start(&self) @dynamic {
  HashMap{String, JsonValue} d;
  d.init(mem);
  self.output.push({ .kind = JsonValueKind.DICT, .value = { .d = d } });
}

fn void? JsonSerializer.struct_end(&self) @dynamic {}

fn void? JsonSerializer.serialize_slice_start(&self) @dynamic {
}
fn void? JsonSerializer.serialize_slice_end(&self, ulong len) @dynamic {
  List{JsonValue} l;
  l.init(mem);
  for (int i = 0; i < len; i++) {
    l.push_front(self.output.pop()!);
  }
  self.output.push({ .kind = JsonValueKind.ARRAY, .value = { .l = l } });
}

// fn void? JsonSerializer.serialize_slice(&self, Serializable[] items) @dynamic {
//   List{JsonValue} l;
//   l.init(mem);
//   foreach (item : items) {
//     JsonSerializer ser;
//     JsonValue value = ser::serialize(&ser, item)!;
//     value.print()!;
//
//     l.push(value);
//   }
//
//   self.output = maybe::value({ .kind = JsonValueKind.ARRAY, .value = { .l = l } });
// }

// fn void? JsonSerializer.serialize_field(&self, String name, Serializable v) @dynamic {
//   JsonValue output = self.output.get()!;
//   if (output.kind != JsonValueKind.DICT) return INVALID_JSON_TYPE~;
//
//   JsonSerializer ser;
//   JsonValue value = ser::serialize(&ser, v)!;
//
//   output.value.d.set(name, value);
//   self.output.set(output);
// }

fn void? JsonSerializer.serialize_field_start(&self, String name) @dynamic {
  self.output.push({.kind = STRING, .value = {.s = name}});
}

fn void? JsonSerializer.serialize_field_end(&self) @dynamic {
  JsonValue value = self.output.pop()!;
  JsonValue key = self.output.pop()!;
  JsonValue obj = self.output.pop()!;
  if (obj.kind != JsonValueKind.DICT) return INVALID_JSON_TYPE~;
  if (key.kind != JsonValueKind.STRING) return INVALID_JSON_TYPE~;

  obj.value.d.set(key.value.s, value);
  self.output.push(obj);
}

fn JsonValue? JsonSerializer.result(&self) => self.output.pop();

// macro void? JsonSerializer.serialize_struct_start(JsonSerializer* self) {
//   HashMap{String, JsonValue} d;
//   self.output = maybe::value({ .kind = JsonValueKind.DICT, .value = { .d = d.init(mem) } });
// }
// macro JsonValue? JsonSerializer.serialize_struct_end(JsonSerializer* self) {
//   return self.output.get();
// }
//
// macro void? JsonSerializer.@serialize_field(JsonSerializer* self, String k, #v) {
//   JsonValue output = self.output.get()!;
//   if (output.kind != JsonValueKind.DICT) return INVALID_JSON_TYPE~;
//
//   JsonValue key = self.serialize_string(k)!;
//   if (key.kind != JsonValueKind.STRING) return INVALID_JSON_TYPE~;
//
//   JsonValue value = ser::@serialize(new_json_serializer(), #v)!;
//
//   output.value.d.set(key.value.s, value);
// }
//
//
// macro void? JsonSerializer.serialize_slice_start(JsonSerializer* self) {
//   List{JsonValue} l;
//   self.output = maybe::value({ .kind = JsonValueKind.ARRAY, .value = { .l = l.init(mem) } });
// }
// macro JsonValue? JsonSerializer.serialize_slice_end(JsonSerializer* self) {
//   return self.output.get();
// }
// macro void? JsonSerializer.@serialize_slice_item(JsonSerializer* self, item) {
//   JsonValue output = self.output.get()!;
//   if (output.kind != JsonValueKind.ARRAY) return INVALID_JSON_TYPE~;
//
//   JsonValue value = ser::@serialize(new_json_serializer(), item)!;
//
//   output.value.l.push(value);
// }
// macro JsonValue? JsonSerializer.@serialize_slice(JsonSerializer* self, items) {
//   List{JsonValue} l;
//   l.init(mem);
//   for (int i = 0; i < items.len; i++) {
//     var s = new_json_serializer();
//     JsonValue value = ser::@serialize(s, items[i])!;
//
//     if (items[i].name == "Sharpie") {
//       l.push(value);
//     }
//   }
//
//   return { .kind = JsonValueKind.ARRAY, .value = { .l = &l } };
// }
//
// fn JsonValue? serialize_slice(JsonSerializer* self, Item[] items) <Item> {
//   List{JsonValue} l;
//   l.init(mem);
//   foreach (item : items) {
//     JsonValue value = ser::@serialize(new_json_serializer(), item)!;
//     value.print()!;
//
//     l.push(value);
//   }
//
//   return { .kind = JsonValueKind.ARRAY, .value = { .l = &l } };
// }
