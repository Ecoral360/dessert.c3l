# Dessert 🍰

A universal serialization and deserialization library for the [C3 programming language](https://c3-lang.org/).

## Goal

Dessert provides a flexible, type-safe framework for converting C3 structs to and from various formats (ex: JSON). It uses compile-time macros to generate serialization/deserialization code, ensuring type safety and minimal runtime overhead.

The library is designed around two core interfaces:
- **Serializer**: Converts C3 structs into a target format
- **Deserializer**: Parses data from a format back into C3 structs

## Features

### Serialization

- Recursive struct serialization (nested structs)
- Support for `Maybe` fields (optional values)
- Support for slice/array fields
- Skip specific fields during serialization
- Rename fields for the output
- Validate field values before serialization
- Support for primitive types: `int`, `bool`, `String`, `char`

### Deserialization

- Handle nested structures
- Support for `Maybe` fields
- Support for slice/array fields
- Field renaming support (different name in the format and in C3)
- Duplicate key detection


### JSON

The `dessert::json` provides a serializer and deserializer for the JSON format.

### Attributes

Use the `@Dessert` attribute to customize serialization/deserialization behavior:

```c3
struct Person (Serializable, Deserializable) {
    int age;                           // Serialized as "age"
    String name;                       // Serialized as "name"
    bool is_cool @Dessert({ .skip = true });  // Skipped during serialization
    Maybe{Person*} friend @Dessert({ .rename = "my_friend" }); // Renamed to "my_friend"
    int score @Dessert({ .validator = "validate_score" }); // Validated before serialization
}
```

**Available attribute options:**

| Option | Type | Description |
|--------|------|-------------|
| `.skip` | `bool` | Skip this field during serialization/deserialization |
| `.rename` | `String` | Use a different name for this field in the output/input |
| `.validator` | `String` | Call a validation method before serialization |

## Installation

Add Dessert to your `project.json`:

```json
{
    "libs": [
        "dessert"
    ]
}
```

## Usage

### 1. Define Your Struct

Implement the `Serializable` and `Deserializable` interfaces using the `impl_serialize` and `impl_deserialize` macros:

```c3
struct Animal (Serializable, Deserializable) {
    String name;
    String specie;
}

fn void? Animal.serialize(&self, Serializer serializer) @dynamic => 
    ser::impl_serialize(serializer, self);

fn void? Animal.deserialize(&self, Deserializer deserializer) @dynamic => 
    des::impl_deserialize(deserializer, self);
```

### 2. Serialize to JSON

```c3
Animal sharpie = { .specie = "Cat", .name = "Sharpie" };
JsonValue? sharpie_json = ser::serialize(json::serializer(), sharpie);
```

### 3. Deserialize from JSON

```c3
Animal? animal = des::deserialize{Animal}(json::deserializer(sharpie_json));
```

## Complete Example

```c3
module myapp;
import dessert;
import dessert::ser;
import dessert::des;
import dessert::json;

struct Animal (Serializable, Deserializable) {
    String name;
    String specie;
}

fn void? Animal.serialize(&self, Serializer serializer) @dynamic => 
    ser::impl_serialize(serializer, self);

fn void? Animal.deserialize(&self, Deserializer deserializer) @dynamic => 
    des::impl_deserialize(deserializer, self);

struct Person (Serializable, Deserializable) {
    int age;
    String name;
    Animal[] pets;
    Maybe{Person*} friend @Dessert({ .rename = "my_friend" });
    bool is_cool @Dessert({ .skip = true });
}

fn void? Person.serialize(&self, Serializer serializer) @dynamic => 
    ser::impl_serialize(serializer, self); 

fn void? Person.deserialize(&self, Deserializer deserializer) @dynamic =>
    des::impl_deserialize(deserializer, self);

fn int main(String[] args) {
    // Create a person with pets
    Animal sharpie = { .name = "Sharpie", .specie = "Cat" };
    Person connor = { .age = 20, .name = "Connor", .is_cool = true };
    connor.pets = { sharpie };

    // Serialize to JSON
    JsonValue? json = ser::serialize(&&json::serializer(), connor);
    
    // Deserialize back to struct
    Person? p = des::deserialize{Person}(&&json::deserializer(json));
    
    return 0;
}
```

## Architecture

### Serializer Interface

```c3
interface Serializer {
    fn void? serialize_bool(bool b);
    fn void? serialize_int(int i);
    fn void? serialize_string(String s);
    fn void? serialize_null();
    fn void? serialize_slice_start();
    fn void? serialize_slice_end(ulong len);
    fn void? serialize_field_start(String name);
    fn void? serialize_field_end();
    fn void? struct_start();
    fn void? struct_end();
}
```

### Deserializer Interface

```c3
interface Deserializer {
    fn void? struct_start();
    fn bool? has_next_field();
    fn String? next_field_name();
    fn void? struct_end();
    fn void? slice_start();
    fn bool? has_next_slice_item();
    fn void? slice_end();
    fn String? next_string();
    fn int? next_int();
    fn double? next_double();
    fn bool? next_bool();
    fn bool? next_null();
}
```

### Adding Support for New Formats

To add support for a new format (e.g., YAML, MessagePack), implement the `Serializer` and `Deserializer` interfaces:

```c3
struct MySerializer (Serializer) {
    // Your implementation
}

fn void? MySerializer.serialize_int(&self, int i) @dynamic {
    // Format-specific implementation
}
```

## Roadmap

- [x] Serialize to JSON
- [x] Recursive struct serialization
- [x] Serialize Maybe fields
- [x] Serialize slice fields
- [x] Serialize struct fields
- [x] Skip field
- [x] Rename field
- [x] Validate field
- [x] Deserialize from JSON
- [ ] Serialize enum fields
- [ ] Serialize union fields

## License

MIT License
