module json;
import std::collections::map;
import std::collections::list;
import std::io;
import dessert::des;

enum JsonValueKind {
  INT,
  FLOAT,
  BOOL,
  STRING,
  DICT,
  ARRAY,
  NULL,
}

struct JsonValue (Printable) {
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

fn String? JsonValue.to_string(self) {
  switch(self.kind) {
    case NULL:
      return "null";
    case INT:
      return string::format(mem, "%s", self.value.i);
    case FLOAT:
      return string::format(mem, "%s", self.value.f);
    case BOOL:
      return string::format(mem, "%s", self.value.b);
    case STRING:
      return string::format(mem, "\"%s\"", self.value.s);
    case ARRAY:
      DString s;
      s.init(mem);
      s.append("[");
      ulong l_len = self.value.l.len();
      foreach (i, item : self.value.l) {
        s.append(item.to_string()!);
        if (i < l_len - 1) {
          s.append(", ");
        }
      }
      s.append("]");
      return s.str_view();
    case DICT:
      DString s;
      s.init(mem);
      s.append("{");
      ulong d_len = self.value.d.len();
      
      foreach (i, entry : self.value.d.iter()) {
        s.append(string::format(mem, "\"%s\": ", entry.key));
        s.append(entry.value.to_string()!);
        if (i < d_len - 1) {
          s.append(", ");
        }
      };
      s.append("}");
      return s.str_view();

    default:
      return NOT_FOUND~;
  }
}


module dessert::json;
import dessert::ser;
import dessert::des;
import json;
import std::collections::maybe;
import std::collections::list;
import std::collections::map;
import std::io;

faultdef INVALID_JSON_TYPE;

struct JsonSerializer (Serializer) {
  List{JsonValue} output;
}

fn JsonSerializer serializer() {
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

fn void? JsonSerializer.serialize_slice_start(&self) @dynamic {}
fn void? JsonSerializer.serialize_slice_end(&self, ulong len) @dynamic {
  List{JsonValue} l;
  l.init(mem);
  for (int i = 0; i < len; i++) {
    l.push_front(self.output.pop()!);
  }
  self.output.push({ .kind = JsonValueKind.ARRAY, .value = { .l = l } });
}

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


// module dessert::json::des;
// import dessert::des;
// import json;
// import std::core::ascii;
// import std::encoding::json;
// import std::io;

faultdef 
  INVALID_OBJECT, 
  INVALID_FIELD, 
  INVALID_ARRAY, 
  INVALID_STRING,
  INVALID_ESCAPE,
  INVALID_NUMBER,
  INVALID_BOOLEAN,
  INVALID_NULL;

struct JsonDeserializer (Deserializer) {
  // JsonValue input;
  StringIterator input;
}

fn void? JsonDeserializer.skip_whitespace(&self) {
  while (self.input.has_next() && ascii::is_blank((char) self.input.peek()!)) {
    (void)self.input.next()!;
  }
}

fn JsonDeserializer? deserializer(JsonValue input) {
  return { .input = { .utf8 = input.to_string()! } };
}

fn void? JsonDeserializer.struct_start(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.input.next()! != '{') {
    return INVALID_OBJECT~;
  }
}

fn bool? JsonDeserializer.has_next_field(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  if (next != '}') {
    if (next == ',') self.input.next()!;
    return true;
  }
  return false;
}

fn String? JsonDeserializer.next_field_name(&self) @dynamic {
  String field_name = self.next_string()!;
  self.skip_whitespace()!;
  if (self.input.next()! != ':') {
    return INVALID_FIELD~;
  }

  return field_name;
}

fn void? JsonDeserializer.struct_end(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.input.next()! != '}') {
    return INVALID_OBJECT~;
  }
}

fn void? JsonDeserializer.slice_start(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.input.next()! != '[') {
    return INVALID_ARRAY~;
  }
}
fn bool? JsonDeserializer.has_next_slice_item(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next =self.input.peek()!;
  if (next != ']') {
    if (next == ',') self.input.next()!;
    return true;
  }
  return false;
}
fn void? JsonDeserializer.slice_end(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.input.next()! != ']') {
    return INVALID_ARRAY~;
  }
}

fn String? JsonDeserializer.next_string(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.input.next()! != '"') {
    return INVALID_STRING~;
  }
  DString val;
  val.init(mem);
  while (Char32 c = self.input.next()!, c != '"') {
    if (c == '\\') {
      Char32 escape = self.input.next()!;
      switch (escape) {
        case 'n':
          val.append('\n');
        case 'r':
          val.append('\r');
        case 't':
          val.append('\t');
        case '"':
          val.append('\"');
        case '\'':
          val.append('\'');
        case '\\':
          val.append('\\');
        default:
          return INVALID_ESCAPE~;
      }
    } else {
      val.append(c);
    }
  }

  // io::printfn("%c", self.input.peek()!);
  // io::printfn("%s", val);

  return val.str_view();
}

<* 
  Source (inspired by): https://github.com/c3lang/c3c/blob/d8636af7fa0edda737ac4c033f4fb3b7660ebede/lib/std/encoding/json.c3#L391
*>
fn double? JsonDeserializer.next_double(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 c = self.input.peek()!;
  @stack_mem(256; Allocator mem) {
    DString t = dstring::new_with_capacity(mem, 32);
    bool negate = c == '-';
    if (negate) {
      self.input.next()!;
      t.append(c);
      c = self.input.peek()!;
    }
    bool leading_zero = c == '0';
    while (ascii::is_digit((char) c)) {
      self.input.next()!;
      t.append(c);
      c = self.input.peek()!;
      if (leading_zero) {
        if (ascii::is_digit((char) c)) return INVALID_NUMBER~;
        leading_zero = false;
      }
    }
    if (c == '.') {
      self.input.next()!;
      t.append(c);
      while (c = self.input.peek()!, ascii::is_digit((char) c)) {
        self.input.next()!;
        t.append(c);
      }
    }
    if ((c | 32) == 'e') {
      self.input.next()!;
      t.append(c);
      c = self.input.next()!;
      switch (c) {
        case '-':
        case '+':
          self.input.next()!;
          t.append(c);
          c = self.input.peek()!;
      }
      if (!ascii::is_digit((char) c)) return INVALID_NUMBER~;
      while (ascii::is_digit((char) c)) {
      self.input.next()!;
        t.append(c);
        c = self.input.peek()!;
      }
    }
    double? d = t.str_view().to_double() ?? INVALID_NUMBER~;
    return d;
  };
}

fn int? JsonDeserializer.next_int(&self) @dynamic {
  return (int) self.next_double()!;
}
fn bool? JsonDeserializer.next_bool(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.next()!;
  switch (next) {
    case 't':
      $foreach $v : "rue": // skips 'rue'
        self.input.next()!;
      $endforeach
      return true;
    case 'f':
      $foreach $v : "alse": // skips 'alse'
        self.input.next()!;
      $endforeach
      return false;
    default:
      return INVALID_BOOLEAN~;
  }
}

fn bool? JsonDeserializer.next_null(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  switch (next) {
    case 'n':
      $foreach $v : "null":
        self.input.next()!;
      $endforeach
      return true;
    default:
      return false;
  }
}
