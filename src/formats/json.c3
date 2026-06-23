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
    long i;
    double f;
    bool b;
    String s;
    OrderedMap{String, JsonValue} d;
    List{JsonValue} l;
  }

  JsonValueKind kind;
}

fn void JsonValue.free(self) {
  switch(self.kind) {
    case NULL:
    case INT:
    case FLOAT:
    case BOOL:
    case STRING:
      break;
    case ARRAY:
      foreach (item : self.value.l) {
        item.free();
      }
      self.value.l.free();
    case DICT:
      self.value.d.@each_entry(; entry) {
        entry.value.free();
      };
      self.value.d.free();
  }

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
      long l_len = self.value.l.len();
      foreach (i, item : self.value.l) {
        item.print()!;
        if (i < l_len - 1) {
          io::print(", ");
        }
      }
     io::printf("]");
    case DICT:
      io::printf("{");
      long d_len = self.value.d.len();
      
      int i = 0;
      self.value.d.@each_entry(; entry) {
        io::printf("\"%s\": ", entry.key);
        entry.value.print()!;
        if (i < d_len - 1) {
          io::print(", ");
        }
        i++;
      };
      io::printf("}");

    // default:
    //   return NOT_FOUND~;
  }
}

fn String? JsonValue.to_string(self) {
  switch(self.kind) {
    case NULL:
      return "null";
    case INT:
      return string::tformat("%s", self.value.i);
    case FLOAT:
      return string::tformat("%s", self.value.f);
    case BOOL:
      return string::tformat("%s", self.value.b);
    case STRING:
      return string::tformat("\"%s\"", self.value.s.treplace("\"", "\\\""));
    case ARRAY:
      DString s;
      s.init(tmem);
      s.append("[");
      long l_len = self.value.l.len();
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
      s.init(tmem);
      s.append("{");
      long d_len = self.value.d.len();
      
      int i = 0;
      self.value.d.@each_entry(; entry) {
        s.append(string::tformat("\"%s\": ", entry.key.treplace("\"", "\\\"")));
        s.append(entry.value.to_string()!);
        if (i < d_len - 1) {
          s.append(", ");
        }
        i++;
      };
      s.append("}");
      return s.str_view();

    // default:
    //   return NOT_FOUND~;
  }
}

fn String to_pretty_string(JsonValue self, int indent = 2, int depth = 0) @private {
  DString pad;
  pad.init(tmem);
  defer pad.free();
  pad.append_repeat(' ', (usz) (indent * depth));

  DString inner_pad;
  inner_pad.init(tmem);
  inner_pad.append_repeat(' ', (usz) (indent * (depth + 1)));

  switch (self.kind) {
    case NULL:
      return "null";
    case INT:
      return string::tformat("%d", self.value.i);
    case FLOAT:
      return string::tformat("%g", self.value.f);
    case BOOL:
      return string::tformat("%s", self.value.b ? "true" : "false");
    case STRING:
      return string::tformat("\"%s\"", self.value.s.treplace("\"", "\\\""));
    case ARRAY:
      DString s;
      s.init(tmem);
      long l_len = self.value.l.len();
      if (l_len == 0) return "[]";
      s.append("[\n");
      foreach (i, item : self.value.l) {
        s.append(inner_pad);
        s.append(to_pretty_string(item, indent, depth + 1));
        if (i < l_len - 1) s.append(",");
        s.append("\n");
      }
      s.append(pad);
      s.append("]");
      return s.str_view();
    case DICT:
      DString s;
      s.init(tmem);
      long d_len = self.value.d.len();
      if (d_len == 0) return "{}";
      s.append("{\n");
      int i = 0;
      self.value.d.@each_entry(; entry) {
        s.append(inner_pad);
        s.append(string::tformat("\"%s\": ", entry.key.treplace("\"", "\\\"")));
        s.append(to_pretty_string(entry.value, indent: indent, depth: depth + 1));
        if (i < d_len - 1) s.append(",");
        s.append("\n");
        i++;
      };
      s.append(pad);
      s.append("}");
      return s.str_view();
  }
}

fn String JsonValue.to_pretty_string(self, int indent = 2) {
  return to_pretty_string(self, indent);
}


module dessert::format::json;
import dessert::ser;
import dessert::des;
import json;
import std::collections::maybe;
import std::collections::list;
import std::collections::map;
import std::collections::object;
import std::io;
import std::math;

faultdef INVALID_JSON_TYPE;

struct JsonSerializer (Serializer) {
  List{JsonValue} output;
  Allocator allocator;
}

fn JsonSerializer serializer(Allocator allocator = tmem) {
  List{JsonValue} output;
  output.init(allocator);
  return { .output = output, .allocator = allocator };
}

fn void? JsonSerializer.serialize_null(&self) @dynamic {
  self.output.push({ .kind = JsonValueKind.NULL, .value = { .i = 0 } });
}

fn void? JsonSerializer.serialize_bool(&self, bool b) @dynamic {
  self.output.push({ .kind = JsonValueKind.BOOL, .value = { .b = b } });
}

fn void? JsonSerializer.serialize_long(&self, long i) @dynamic {
  self.output.push({ .kind = JsonValueKind.INT, .value = { .i = i } });
}

fn void? JsonSerializer.serialize_double(&self, double f) @dynamic {
  self.output.push({ .kind = JsonValueKind.FLOAT, .value = { .f = f } });
}

fn void? JsonSerializer.serialize_string(&self, String s) @dynamic {
  self.output.push({ .kind = JsonValueKind.STRING, .value = { .s = s } });
}

fn void? JsonSerializer.struct_start(&self, String name) @dynamic {
  OrderedMap{String, JsonValue} d;
  d.init(self.allocator);
  self.output.push({ .kind = JsonValueKind.DICT, .value = { .d = d } });
}

fn void? JsonSerializer.struct_end(&self, String name) @dynamic {}

fn void? JsonSerializer.serialize_slice_start(&self, long len) @dynamic {}
fn void? JsonSerializer.serialize_slice_end(&self, long len) @dynamic {
  List{JsonValue} l;
  l.init(self.allocator);
  for (int i = 0; i < len; i++) {
    l.push_front(self.output.pop()!);
  }
  self.output.push({ .kind = JsonValueKind.ARRAY, .value = { .l = l } });
}

fn void? JsonSerializer.serialize_field_start(&self, String name, FieldAttrs fmt) @dynamic {
  self.output.push({.kind = STRING, .value = {.s = name}});
}

fn void? JsonSerializer.serialize_field_end(&self, String name, FieldAttrs fmt) @dynamic {
  JsonValue value = self.output.pop()!;
  JsonValue key = self.output.pop()!;
  JsonValue obj = self.output.pop()!;
  if (obj.kind != JsonValueKind.DICT) return INVALID_JSON_TYPE~;
  if (key.kind != JsonValueKind.STRING) return INVALID_JSON_TYPE~;

  obj.value.d.set(key.value.s, value);
  self.output.push(obj);
}

fn JsonValue? JsonSerializer.result(&self) => self.output.pop();


struct JsonStringSerializer (Serializer) {
  DString output;
}

fn JsonStringSerializer string_serializer(Allocator allocator = tmem) {
  DString output;
  output.init(allocator);
  return { .output = output };
}

fn void? JsonStringSerializer.serialize_null(&self) @dynamic {
  self.output.append("null");
}

fn void? JsonStringSerializer.serialize_bool(&self, bool b) @dynamic {
  self.output.append(b ? "true" : "false");
}

fn void? JsonStringSerializer.serialize_long(&self, long i) @dynamic {
  self.output.append(string::tformat("%d", i));
}

fn void? JsonStringSerializer.serialize_double(&self, double f) @dynamic {
  self.output.append(string::tformat("%f", f));
}

fn void? JsonStringSerializer.serialize_string(&self, String s) @dynamic {
  self.output.append("\"");
  self.output.append(s.treplace("\"", "\\\""));
  self.output.append("\"");
}

fn void? JsonStringSerializer.struct_start(&self, String name) @dynamic {
  self.output.append("{");
}

fn void? JsonStringSerializer.struct_end(&self, String name) @dynamic {
  if (self.output[^1] == ',') {
    self.output.chop(self.output.len() - 1);
  }
  self.output.append("}");
}

fn void? JsonStringSerializer.serialize_slice_start(&self, long len) @dynamic {
  self.output.append("[");
}

fn void? JsonStringSerializer.serialize_slice_end(&self, long len) @dynamic {
  if (len > 0) self.output.chop(self.output.len() - 1);
  self.output.append("]");
}

fn void? JsonStringSerializer.serialize_slice_item_end(&self, usz idx) @dynamic {
  self.output.append(",");
}

fn void? JsonStringSerializer.serialize_field_start(&self, String name, FieldAttrs fmt) @dynamic {
  self.serialize_string(name)!;
  self.output.append(":");
}

fn void? JsonStringSerializer.serialize_field_end(&self, String name, FieldAttrs fmt) @dynamic {
  self.output.append(",");
}

fn String JsonStringSerializer.result(&self) => self.output.str_view();


faultdef
  UNEXPECTED_CHARACTER,
  INVALID_OBJECT,
  INVALID_FIELD,
  INVALID_ARRAY,
  INVALID_STRING,
  INVALID_ESCAPE,
  INVALID_NUMBER,
  INVALID_BOOLEAN,
  INVALID_NULL,
  INVALID_COMMENT;

<*
  Selects how lenient the deserializer is.

  - `JSON`  : strict RFC 8259 JSON.
  - `JSONC` : a relaxed superset (JSON5-style). On top of plain JSON it accepts
    single (`//`) and multi (`/* */`) line comments, unquoted and single-quoted
    object keys, single-quoted strings with extra escapes (`\x`, `\u`, `\b`,
    `\f`, `\v`, `\0`, line continuations and "escape any other char as itself"),
    trailing commas in objects and arrays, hexadecimal numbers,
    leading/trailing decimal points, a leading `+`, `Infinity`, `-Infinity`
    and `NaN`.
*>
enum JsonFlavor {
  JSON,
  JSONC,
}

struct JsonDeserializer(Deserializer) {
  // JsonValue input;
  StringIterator input;
  Allocator allocator;
  Maybe{String} peeked_field;
  int col;
  int line;
  bool is_debug;
  JsonFlavor flavor;
}

fn Char32? JsonDeserializer.next(&self) @inline {
  Char32 c = self.input.next()!;
  if (self.is_debug) {
    if (c == '\n') {
      self.line += 1;
      self.col = 0;
    } else {
      self.col += 1;
    }
  }
  return c;
}

<*
  JSON5/JSONC whitespace: the JSON whitespace plus the rest of the ECMAScript
  whitespace set we can cheaply recognize.
*>
macro bool is_json5_space(Char32 c) @local {
  switch (c) {
    case ' ':
    case '\t':
    case '\n':
    case '\r':
    case '\v':
    case '\f':
    case 0xA0:   // no-break space
    case 0xFEFF: // BOM / zero width no-break space
    case 0x2028: // line separator
    case 0x2029: // paragraph separator
      return true;
    default:
      return false;
  }
}

macro bool is_ident_start(Char32 c) @local {
  return c == '_' || c == '$' || ascii::is_alpha((char) c) || c > 127;
}

macro bool is_ident_part(Char32 c) @local {
  return c == '_' || c == '$' || ascii::is_alpha((char) c) || ascii::is_digit((char) c) || c > 127;
}

<*
  Skips whitespace. In `JSONC` mode it also skips `//` and `/* */` comments and
  recognizes the extended whitespace set.
*>
fn void? JsonDeserializer.skip_whitespace(&self) {
  while (self.input.has_next()) {
    Char32 c = self.input.peek()!;

    bool is_space = self.flavor == JSONC
      ? is_json5_space(c)
      : (ascii::is_blank((char) c) || c == '\n');
    if (is_space) {
      (void) self.next()!;
      continue;
    }

    if (self.flavor == JSONC && c == '/') {
      (void) self.next()!;
      Char32 kind = self.next()!;
      switch (kind) {
        case '/':
          // line comment: consume until newline (or end of input)
          while (self.input.has_next()) {
            Char32 cc = self.input.peek()!;
            if (cc == '\n' || cc == 0x2028 || cc == 0x2029) break;
            (void) self.next()!;
          }
        case '*':
          // block comment: consume until "*/"
          bool closed = false;
          while (self.input.has_next()) {
            Char32 cc = self.next()!;
            if (cc == '*' && self.input.has_next() && self.input.peek()! == '/') {
              (void) self.next()!;
              closed = true;
              break;
            }
          }
          if (!closed) return INVALID_COMMENT~;
        default:
          return INVALID_COMMENT~;
      }
      continue;
    }

    break;
  }
}

macro Type? deserialize(Allocator allocator, String input, JsonFlavor flavor = JSONC) <Type> {
  return des::deserialize{Type}(&&json::deserializer(allocator, input, flavor));
}

macro Type? tdeserialize(String input, JsonFlavor flavor = JSONC) <Type> {
  return des::deserialize{Type}(&&json::tdeserializer(input, flavor));
}

fn JsonDeserializer deserializer(Allocator allocator, String input, JsonFlavor flavor = JSONC) {
  return { .input = { .utf8 = input }, .allocator = allocator, .flavor = flavor };
}

fn JsonDeserializer tdeserializer(String input, JsonFlavor flavor = JSONC) => deserializer(tmem, input, flavor);

fn JsonDeserializer? debug_deserializer(Allocator allocator, String input, JsonFlavor flavor = JSONC) {
  return { .input = { .utf8 = input }, .allocator = allocator, .is_debug = true, .flavor = flavor };
}

fn JsonDeserializer? tdebug_deserializer(String input, JsonFlavor flavor = JSONC) => debug_deserializer(tmem, input, flavor);

fn void? JsonDeserializer.struct_start(&self, String name) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != '{') {
    return UNEXPECTED_CHARACTER~;
  }
}

<*
  In `JSONC` mode a comma right before the closing `}` (trailing comma) ends the
  object instead of being an error.
*>
fn bool? JsonDeserializer.has_next_field(&self) @dynamic {
  if (self.peeked_field.has_value) return true;

  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  if (next == ',') {
    (void) self.next()!;
    if (self.flavor == JSONC) {
      self.skip_whitespace()!;
      next = self.input.peek()!;
    } else {
      return true;
    }
  }
  return next != '}';
}

fn String? JsonDeserializer.next_field_name(&self) @dynamic {
  if (try field_name = self.peeked_field.get()) {
    self.peeked_field.reset();
    return field_name;
  }

  String field_name;
  if (self.flavor == JSONC) {
    self.skip_whitespace()!;
    Char32 next = self.input.peek()!;
    // JSONC keys may be quoted (single or double) or bare identifiers.
    field_name = (next == '"' || next == '\'')
      ? self.next_string()!
      : self.next_identifier()!;
  } else {
    field_name = self.next_string()!;
  }

  self.skip_whitespace()!;
  if (self.next()! != ':') {
    return INVALID_FIELD~;
  }

  return field_name;
}

<*
  Reads an unquoted (ECMAScript identifier) object key. JSONC only.
*>
fn String? JsonDeserializer.next_identifier(&self) {
  self.skip_whitespace()!;
  Char32 first = self.input.peek()!;
  if (!is_ident_start(first)) {
    if (self.is_debug) {
      self.print_error(string::tformat("Expected an identifier, found %c", first));
    }
    return INVALID_FIELD~;
  }

  DString val;
  val.init(self.allocator);
  while (self.input.has_next()) {
    Char32 c = self.input.peek()!;
    if (!is_ident_part(c)) break;
    val.append(c);
    (void) self.next()!;
  }

  if (val.len() == 0) return INVALID_FIELD~;
  return val.str_view();
}

fn String? JsonDeserializer.peek_field_name(&self) @dynamic {
  if (try field_name = self.peeked_field.get()) {
    return field_name;
  }

  String field_name = self.next_field_name()!;
  self.peeked_field = maybe::value(field_name);

  return field_name;
}

fn void? JsonDeserializer.struct_end(&self, String name) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != '}') {
    return UNEXPECTED_CHARACTER~;
  }
}

fn void? JsonDeserializer.slice_start(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != '[') {
    return INVALID_ARRAY~;
  }
}
<*
  In `JSONC` mode a comma right before the closing `]` (trailing comma) ends the
  array instead of being an error.
*>
fn bool? JsonDeserializer.has_next_slice_item(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  if (next == ',') {
    (void) self.next()!;
    if (self.flavor == JSONC) {
      self.skip_whitespace()!;
      next = self.input.peek()!;
    } else {
      return true;
    }
  }
  return next != ']';
}
fn void? JsonDeserializer.slice_end(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != ']') {
    return INVALID_ARRAY~;
  }
}

fn void JsonDeserializer.print_error(&self, String message) {
  io::eprintfn("At %d:%d: %s", self.line, self.col, message);
}

fn Object*? JsonDeserializer.next_any(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  bool jsonc = self.flavor == JSONC;
  switch {
    case next == '"':
      return object::new_string(self.allocator, self.next_string())!;

    case next == '\'':
      if (!jsonc) return UNEXPECTED_CHARACTER~;
      return object::new_string(self.allocator, self.next_string())!;

    case next == 't':
    case next == 'f':
      return object::new_bool(self.next_bool())!;

    case next == 'n':
      (void)self.next_null()!;
      return object::new_null();

    case next == '{':
      Object* o = object::new_obj(self.allocator);
      self.struct_start("")!;
      while(self.has_next_field()!) {
        String next_key = self.next_field_name()!;
        o.set(next_key, self.next_any())!;
      }
      self.struct_end("")!;
      return o;

    case next == '[':
      Object* o = object::new_obj(self.allocator);
      self.slice_start()!;
      while(self.has_next_slice_item()!) {
        o.push(self.next_any())!;
      }
      self.slice_end()!;
      return o;

    case ascii::is_digit((char) next):
    case next == '-':
    case next == '+':
    case next == '.':
    case next == 'I':
    case next == 'N':
      // '+', '.', 'I' (Infinity) and 'N' (NaN) only start a number in JSONC.
      if (!jsonc && (next == '+' || next == '.' || next == 'I' || next == 'N')) {
        return UNEXPECTED_CHARACTER~;
      }
      double value = self.next_double()!;
      if (!math::is_nan(value) && !math::is_inf(value) && (double) math::round(value) == value) {
        return object::new_int(self.allocator, (int128) value);
      }
      return object::new_float(self.allocator, value);
  }

  return UNEXPECTED_CHARACTER~;
}

fn String? JsonDeserializer.next_string(&self) @dynamic {
  self.skip_whitespace()!;
  bool jsonc = self.flavor == JSONC;
  Char32 quote = self.next()!;
  // JSONC also allows single-quoted strings.
  bool ok_quote = quote == '"' || (jsonc && quote == '\'');
  if (!ok_quote) {
    if (self.is_debug) {
      self.print_error(string::tformat("Expected \", found %c", quote));
    }
    return INVALID_STRING~;
  }
  DString val;
  val.init(self.allocator);
  while (true) {
    Char32 c = self.next()!;
    if (c == quote) break;

    if (c == '\\') {
      Char32 escape = self.next()!;
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
          if (!jsonc) return INVALID_ESCAPE~;
          // JSONC-only escapes.
          switch (escape) {
            case 'b':
              val.append('\b');
            case 'f':
              val.append('\f');
            case 'v':
              val.append('\v');
            case '0':
              val.append('\0');
            case '/':
              val.append('/');
            case 'x':
              val.append(self.read_hex(2)!);
            case 'u':
              uint num = self.read_hex(4)!;
              switch
              {
                case num >= 0xDC00 && num <= 0xDFFF:
                  // Lone surrogate
                  return INVALID_ESCAPE~;
                case num >= 0xD800 && num <= 0xDBFF:
                  // High surrogate read, now look for low surrogate
                  if (self.next()! != '\\') return INVALID_ESCAPE~;
                  if (self.next()! != 'u') return INVALID_ESCAPE~;
                  uint low = self.read_hex(4)!;
                  if (low < 0xDC00 || low > 0xDFFF) return INVALID_ESCAPE~;
                  num = 0x10000u + (num - 0xD800u) << 10u + (low - 0xDC00u);
              }
              val.append_char32(num);
            case '\n':
            case 0x2028:
            case 0x2029:
              // line continuation: drop the newline
              break;
            case '\r':
              // line continuation, consume an optional trailing \n
              if (self.input.has_next() && self.input.peek()! == '\n') (void) self.next()!;
            default:
              return INVALID_ESCAPE~;
              // val.append(escape);
          }
      }
    } else {
      val.append(c);
    }
  }

  return val.str_view();
}

<*
  Reads `count` hexadecimal digits and returns the resulting code point. JSONC.
*>
fn uint? JsonDeserializer.read_hex(&self, int count) {
  uint result;
  for (int i = 0; i < count; i++) {
    char c = (char) self.next()!;
    if (!((char) c).is_xdigit()) return INVALID_ESCAPE~;
    result = result << 4u + (c > '9' ? (c | 32u) - 'a' + 10u : c - '0');
  }
  return result;
}

<*
  Parses the accumulated number text, applying the sign. Centralizes the
  "invalid number" error so the various early-exit paths share it.
*>
fn double? parse_double(String s, bool negate) @local {
  double? value = s.to_double();
  if (catch value) return INVALID_NUMBER~;
  return negate ? -value : value;
}

<* 
  Source (inspired by): https://github.com/c3lang/c3c/blob/d8636af7fa0edda737ac4c033f4fb3b7660ebede/lib/std/encoding/json.c3#L391
*>
fn double? JsonDeserializer.next_double(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 c = self.input.peek()!;
  bool jsonc = self.flavor == JSONC;

  @stack_mem(256; Allocator mem) {
    DString t = dstring::new_with_capacity(mem, 32);

    // Sign: a leading '+' is only valid in JSONC.
    bool negate = false;
    if (c == '-' || c == '+') {
      if (c == '+' && !jsonc) return INVALID_NUMBER~;
      negate = c == '-';
      self.next()!;
      c = self.input.peek()!;
    }

    // Infinity / NaN (JSONC only).
    if (jsonc) {
      if (c == 'I') {
        foreach (ch : "Infinity") if (self.next()! != ch) return INVALID_NUMBER~;
        double zero = 0.0;
        return negate ? -1.0 / zero : 1.0 / zero;
      }
      if (c == 'N') {
        foreach (ch : "NaN") if (self.next()! != ch) return INVALID_NUMBER~;
        double zero = 0.0;
        return zero / zero;
      }
    }

    // Hexadecimal (JSONC only): a '0' followed by 'x'/'X'.
    bool leading_zero = c == '0';
    if (jsonc && c == '0') {
      t.append(c);
      self.next()!;
      Char32? after = self.input.peek();
      if (catch after) return parse_double(t.str_view(), negate);
      if (after == 'x' || after == 'X') {
        self.next()!;
        uint128 hex = 0;
        bool has_digit = false;
        while (self.input.has_next()) {
          Char32 h = self.input.peek()!;
          uint digit;
          if (h >= '0' && h <= '9') {
            digit = (uint) (h - '0');
          } else if (h >= 'a' && h <= 'f') {
            digit = (uint) (h - 'a' + 10);
          } else if (h >= 'A' && h <= 'F') {
            digit = (uint) (h - 'A' + 10);
          } else {
            break;
          }
          hex = hex * 16 + digit;
          has_digit = true;
          self.next()!;
        }
        if (!has_digit) return INVALID_NUMBER~;
        double result = (double) hex;
        return negate ? -result : result;
      }
      c = after;
      leading_zero = false; // the '0' has already been consumed
    }

    // Integer part.
    while (ascii::is_digit((char) c)) {
      self.next()!;
      t.append(c);
      Char32? next = self.input.peek();
      if (catch next) return parse_double(t.str_view(), negate);
      c = next;
      // Strict JSON forbids leading zeros (e.g. "01"); JSONC is lenient.
      if (!jsonc && leading_zero) {
        if (ascii::is_digit((char) c)) return INVALID_NUMBER~;
        leading_zero = false;
      }
    }

    // Fraction (a leading or trailing decimal point is not accepted).
    if (c == '.') {
      self.next()!;
      t.append(c);
      Char32? next = self.input.peek();
      if (catch next) return INVALID_NUMBER~;
      c = next;
      while (ascii::is_digit((char) c)) {
        self.next()!;
        t.append(c);
        Char32? next2 = self.input.peek();
        if (catch next2) return parse_double(t.str_view(), negate);
        c = next2;
      }
      if (t[^1] == '.') return INVALID_NUMBER~;
    }

    // Exponent.
    if ((c | 32) == 'e') {
      self.next()!;
      t.append(c);
      Char32? after = self.input.peek();
      if (catch after) return INVALID_NUMBER~;
      c = after;
      if (c == '-' || c == '+') {
        self.next()!;
        t.append(c);
        Char32? sexp = self.input.peek();
        if (catch sexp) return INVALID_NUMBER~;
        c = sexp;
      }
      if (!ascii::is_digit((char) c)) return INVALID_NUMBER~;
      while (ascii::is_digit((char) c)) {
        self.next()!;
        t.append(c);
        Char32? next = self.input.peek();
        if (catch next) return parse_double(t.str_view(), negate);
        c = next;
      }
    }

    return parse_double(t.str_view(), negate);
  };
}

fn char? JsonDeserializer.next_char(&self) @dynamic {
  return (char) self.next_double()!;
}

fn long? JsonDeserializer.next_long(&self) @dynamic {
  return (long) self.next_double()!;
}

fn bool? JsonDeserializer.next_bool(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.next()!;
  switch (next) {
    case 't':
      $foreach $v : "rue": // skips 'rue'
        self.next()!;
      $endforeach
      return true;
    case 'f':
      $foreach $v : "alse": // skips 'alse'
        self.next()!;
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
        self.next()!;
      $endforeach
      return true;
    default:
      return false;
  }
}
