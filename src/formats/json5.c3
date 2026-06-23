module dessert::format::json5;
import dessert::ser;
import dessert::des;
import std::collections::maybe;
import std::collections::list;
import std::collections::map;
import std::collections::object;
import std::io;
import std::math;

<*
  A deserializer for the JSON5 format (https://json5.org).

  JSON5 is a superset of JSON. On top of plain JSON, this deserializer accepts:
    - single (`//`) and multi (`/* */`) line comments,
    - unquoted and single-quoted object keys,
    - single-quoted strings and extra string escapes (`\x`, `\u`, `\b`, `\f`,
      `\v`, `\0`, line continuations and "escape any other char as itself"),
    - trailing commas in objects and arrays,
    - hexadecimal numbers, leading/trailing decimal points, a leading `+`,
      `Infinity`, `-Infinity` and `NaN`.

  It mirrors the structure of `dessert::format::json::JsonDeserializer`.
*>

faultdef
  INVALID_OBJECT,
  INVALID_FIELD,
  INVALID_ARRAY,
  INVALID_STRING,
  INVALID_ESCAPE,
  INVALID_NUMBER,
  INVALID_BOOLEAN,
  INVALID_NULL,
  INVALID_COMMENT;

struct Json5Deserializer (Deserializer) {
  StringIterator input;
  Allocator allocator;
  Maybe{String} peeked_field;
  int col;
  int line;
  bool is_debug;
}

fn Json5Deserializer? deserializer(Allocator allocator, String input) {
  return { .input = { .utf8 = input }, .allocator = allocator };
}

fn Json5Deserializer? tdeserializer(String input) => deserializer(tmem, input);

fn Json5Deserializer? debug_deserializer(Allocator allocator, String input) {
  return { .input = { .utf8 = input }, .allocator = allocator, .is_debug = true };
}

fn Json5Deserializer? tdebug_deserializer(String input) => debug_deserializer(tmem, input);

fn Char32? Json5Deserializer.next(&self) @inline {
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

fn void Json5Deserializer.print_error(&self, String message) {
  io::eprintfn("At %d:%d: %s", self.line, self.col, message);
}

<*
  JSON5 whitespace: the JSON whitespace plus the rest of the ECMAScript
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
  Skips whitespace and comments. Comments are a JSON5 extension and may appear
  anywhere whitespace is allowed.
*>
fn void? Json5Deserializer.skip_whitespace(&self) {
  while (self.input.has_next()) {
    Char32 c = self.input.peek()!;
    if (is_json5_space(c)) {
      (void) self.next()!;
      continue;
    }
    if (c == '/') {
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

fn void? Json5Deserializer.struct_start(&self, String name) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != '{') {
    return INVALID_OBJECT~;
  }
}

fn void? Json5Deserializer.struct_end(&self, String name) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != '}') {
    return INVALID_OBJECT~;
  }
}

<*
  Handles trailing commas: a comma right before the closing `}` ends the object.
*>
fn bool? Json5Deserializer.has_next_field(&self) @dynamic {
  if (self.peeked_field.has_value) return true;

  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  if (next == ',') {
    (void) self.next()!;
    self.skip_whitespace()!;
    next = self.input.peek()!;
  }
  return next != '}';
}

fn String? Json5Deserializer.next_field_name(&self) @dynamic {
  if (try field_name = self.peeked_field.get()) {
    self.peeked_field.reset();
    return field_name;
  }

  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  String field_name;
  if (next == '"' || next == '\'') {
    field_name = self.next_string()!;
  } else {
    field_name = self.next_identifier()!;
  }

  self.skip_whitespace()!;
  if (self.next()! != ':') {
    return INVALID_FIELD~;
  }

  return field_name;
}

fn String? Json5Deserializer.peek_field_name(&self) @dynamic {
  if (try field_name = self.peeked_field.get()) {
    return field_name;
  }

  String field_name = self.next_field_name()!;
  self.peeked_field = maybe::value(field_name);

  return field_name;
}

<*
  Reads an unquoted (ECMAScript identifier) object key.
*>
fn String? Json5Deserializer.next_identifier(&self) {
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

fn void? Json5Deserializer.slice_start(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != '[') {
    return INVALID_ARRAY~;
  }
}

<*
  Handles trailing commas: a comma right before the closing `]` ends the array.
*>
fn bool? Json5Deserializer.has_next_slice_item(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  if (next == ',') {
    (void) self.next()!;
    self.skip_whitespace()!;
    next = self.input.peek()!;
  }
  return next != ']';
}

fn void? Json5Deserializer.slice_end(&self) @dynamic {
  self.skip_whitespace()!;
  if (self.next()! != ']') {
    return INVALID_ARRAY~;
  }
}

fn Object*? Json5Deserializer.next_any(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  switch {
    case next == '"':
    case next == '\'':
      return object::new_string(self.allocator, self.next_string())!;

    case next == 't':
    case next == 'f':
      return object::new_bool(self.next_bool())!;

    case next == 'n':
      (void) self.next_null()!;
      return object::new_null();

    case next == '{':
      Object* o = object::new_obj(self.allocator);
      self.struct_start("")!;
      while (self.has_next_field()!) {
        String next_key = self.next_field_name()!;
        o.set(next_key, self.next_any())!;
      }
      self.struct_end("")!;
      return o;

    case next == '[':
      Object* o = object::new_obj(self.allocator);
      self.slice_start()!;
      while (self.has_next_slice_item()!) {
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
      double value = self.next_double()!;
      if (!math::is_nan(value) && !math::is_inf(value) && (double) math::round(value) == value) {
        return object::new_int(self.allocator, (int128) value);
      }
      return object::new_float(self.allocator, value);
  }

  return INVALID_OBJECT~;
}

fn String? Json5Deserializer.next_string(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 quote = self.next()!;
  if (quote != '"' && quote != '\'') {
    if (self.is_debug) {
      self.print_error(string::tformat("Expected a quote, found %c", quote));
    }
    return INVALID_STRING~;
  }

  DString val;
  val.init(self.allocator);
  while (Char32 c = self.next()!, c != quote) {
    if (c == '\\') {
      Char32 escape = self.next()!;
      switch (escape) {
        case 'n':
          val.append('\n');
        case 'r':
          val.append('\r');
        case 't':
          val.append('\t');
        case 'b':
          val.append('\b');
        case 'f':
          val.append('\f');
        case 'v':
          val.append('\v');
        case '0':
          val.append('\0');
        case '"':
          val.append('"');
        case '\'':
          val.append('\'');
        case '\\':
          val.append('\\');
        case '/':
          val.append('/');
        case 'x':
          val.append(self.read_hex(2)!);
        case 'u':
          val.append(self.read_hex(4)!);
        case '\n':
        case 0x2028:
        case 0x2029:
          // line continuation: drop the newline
          break;
        case '\r':
          // line continuation, consume an optional trailing \n
          if (self.input.has_next() && self.input.peek()! == '\n') (void) self.next()!;
        default:
          // JSON5 allows any other character to be escaped as itself
          val.append(escape);
      }
    } else {
      val.append(c);
    }
  }

  return val.str_view();
}

<*
  Reads `count` hexadecimal digits and returns the resulting code point.
*>
fn Char32? Json5Deserializer.read_hex(&self, int count) {
  uint result = 0;
  for (int i = 0; i < count; i++) {
    Char32 c = self.next()!;
    uint digit;
    switch {
      case c >= '0' && c <= '9':
        digit = (uint) (c - '0');
      case c >= 'a' && c <= 'f':
        digit = (uint) (c - 'a' + 10);
      case c >= 'A' && c <= 'F':
        digit = (uint) (c - 'A' + 10);
      default:
        return INVALID_ESCAPE~;
    }
    result = result * 16 + digit;
  }
  return (Char32) result;
}

fn double? Json5Deserializer.next_double(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 c = self.input.peek()!;

  @stack_mem(256; Allocator mem) {
    DString t = dstring::new_with_capacity(mem, 32);

    bool negate = false;
    if (c == '-' || c == '+') {
      negate = c == '-';
      (void) self.next()!;
      c = self.input.peek()!;
    }

    // Infinity / NaN (JSON5)
    if (c == 'I') {
      foreach (ch : "Infinity") {
        if (self.next()! != ch) return INVALID_NUMBER~;
      }
      double zero = 0.0;
      return negate ? -1.0 / zero : 1.0 / zero;
    }
    if (c == 'N') {
      foreach (ch : "NaN") {
        if (self.next()! != ch) return INVALID_NUMBER~;
      }
      double zero = 0.0;
      return zero / zero;
    }

    // Hexadecimal (JSON5)
    if (c == '0') {
      t.append(c);
      (void) self.next()!;
      Char32? after = self.input.peek();
      if (catch after) {
        return parse_double(t.str_view(), negate);
      }
      if (after == 'x' || after == 'X') {
        (void) self.next()!;
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
          (void) self.next()!;
        }
        if (!has_digit) return INVALID_NUMBER~;
        double result = (double) hex;
        return negate ? -result : result;
      }
      c = after;
    }

    // Decimal: integer part
    while (ascii::is_digit((char) c)) {
      (void) self.next()!;
      t.append(c);
      Char32? next = self.input.peek();
      if (catch next) {
        return parse_double(t.str_view(), negate);
      }
      c = next;
    }

    // Fraction (leading or trailing decimal point allowed in JSON5)
    if (c == '.') {
      (void) self.next()!;
      t.append(c);
      Char32? next = self.input.peek();
      if (catch next) {
        return parse_double(t.str_view(), negate);
      }
      c = next;
      while (ascii::is_digit((char) c)) {
        (void) self.next()!;
        t.append(c);
        Char32? next2 = self.input.peek();
        if (catch next2) {
          return parse_double(t.str_view(), negate);
        }
        c = next2;
      }
    }

    // Exponent
    if ((c | 32) == 'e') {
      (void) self.next()!;
      t.append(c);
      c = self.next()!;
      switch (c) {
        case '-':
        case '+':
          t.append(c);
          c = self.input.peek()!;
      }
      if (!ascii::is_digit((char) c)) return INVALID_NUMBER~;
      while (ascii::is_digit((char) c)) {
        (void) self.next()!;
        t.append(c);
        Char32? next = self.input.peek();
        if (catch next) {
          return parse_double(t.str_view(), negate);
        }
        c = next;
      }
    }

    return parse_double(t.str_view(), negate);
  };
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

fn char? Json5Deserializer.next_char(&self) @dynamic {
  return (char) self.next_double()!;
}

fn long? Json5Deserializer.next_long(&self) @dynamic {
  return (long) self.next_double()!;
}

fn bool? Json5Deserializer.next_bool(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.next()!;
  switch (next) {
    case 't':
      foreach (ch : "rue") if (self.next()! != ch) return INVALID_BOOLEAN~;
      return true;
    case 'f':
      foreach (ch : "alse") if (self.next()! != ch) return INVALID_BOOLEAN~;
      return false;
    default:
      return INVALID_BOOLEAN~;
  }
}

fn bool? Json5Deserializer.next_null(&self) @dynamic {
  self.skip_whitespace()!;
  Char32 next = self.input.peek()!;
  switch (next) {
    case 'n':
      foreach (ch : "null") if (self.next()! != ch) return INVALID_NULL~;
      return true;
    default:
      return false;
  }
}
