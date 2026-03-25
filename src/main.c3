module dessert;
import std::io;
import dessert::ser;
import dessert::json;
import json;
import std::collections::list;
import std::collections::maybe;

struct Animal (Serializable) {
  String name;
  String specie;
}

struct Person (Serializable) {
  int age;
  String name;
  Animal[] pets;
  // Maybe{Animal} pet;
}


fn void? Animal.serialize(&self, Serializer serializer) @dynamic {
  serializer.struct_start()!;

  serializer.serialize_field_start("name")!;
  self.name.serialize(serializer)!;
  serializer.serialize_field_end()!;

  serializer.serialize_field_start("specie")!;
  self.specie.serialize(serializer)!;
  serializer.serialize_field_end()!;

  serializer.struct_end()!;
}

fn void? Person.serialize(&self, Serializer serializer) @dynamic {
  serializer.struct_start()!;
  serializer.serialize_field_start("age")!;
  self.age.serialize(serializer)!;
  serializer.serialize_field_end()!;

  serializer.serialize_field_start("name")!;
  self.name.serialize(serializer)!;
  serializer.serialize_field_end()!;

  serializer.serialize_field_start("pets")!;
  serializer.serialize_slice_start()!;
  foreach (pet : self.pets) {
    pet.serialize(serializer)!;
  }
  serializer.serialize_slice_end(self.pets.len)!;
  serializer.serialize_field_end()!;

  serializer.struct_end()!;
}


fn int main(String[] args)
{
  Person connor = { .age = 20, .name = "Connor" };
  Animal sharpie = { .name = "Sharpie", .specie = "Cat" };
  Animal gisele = { .name = "Gisele", .specie = "Rabbit" };
  connor.pets = {sharpie, gisele};
  // connor.pet = maybe::value(sharpie);
  // connor.pet = sharpie;

  Person amenda = { .age = 21, .name = "Amenda" };

  JsonSerializer ser = json::new_json_serializer();
  JsonValue? connor_json = ser::serialize(&ser, &connor);
  if (catch connor_json) {
	  io::printn("error");
    return 0;
  }

	io::printn("Success");
  connor_json.print()!!;
	io::printn("");

  JsonValue? amenda_json = ser::serialize(&&json::new_json_serializer(), amenda);
  if (catch amenda_json) {
	  io::printn("error");
    return 0;
  }

	io::printn("Success");
  amenda_json.print()!!;
	io::printn("");
	return 0;
}


