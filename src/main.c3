module dessert;
import std::io;
import dessert::ser;
import dessert::des;
import dessert::json;
import json;
import std::collections::list;
import std::collections::maybe;

struct Animal (Serializable, Deserializable) {
  String name;
  String specie;
}

fn void? Animal.serialize(&self, Serializer serializer) @dynamic => 
  ser::impl_serialize(serializer, self);

fn void? Animal.deserialize(&self, Deserializer deserializer) @dynamic => 
  des::impl_deserialize(deserializer, self);

struct Person (Serializable, Deserializable) {
  int age @Dessert({ .validator = "validate_age" });
  String name;
  Animal[] pets;
  Maybe{Person*} friend @Dessert({ .rename = "my_friend" });
  bool is_cool @Dessert({ .skip = true });
}

fn void? Person.serialize(&self, Serializer serializer) @dynamic => 
  ser::impl_serialize(serializer, self); 

fn void? Person.deserialize(&self, Deserializer deserializer) @dynamic =>
  des::impl_deserialize(deserializer, self);

fn bool Person.validate_age(&self, int age) => age > 0;





fn void Person.print(&self) {
  io::print("(Person) { ");
  io::printf(".name = \"%s\", ", self.name);
  io::printf(".age = %s, ", self.age);
  io::printf(".is_cool = %s, ", self.is_cool);
  io::print(".pets = [");
  foreach (i, pet : self.pets) {
    io::printf("(Animal) { .name = \"%s\", .specie = \"%s\" }", pet.name, pet.specie);
    if (i < self.pets.len - 1) {
      io::print(", ");
    }
  }
  io::print("], ");
  io::print(".friend = ");
  if (try friend = self.friend.get()) {
    io::print("Some{ ");
    friend.print();
    io::print("}");
  } else {
    io::print("None");
  }

  io::print(" }");
}

fn int main(String[] args) {
  Person connor = { .age = 20, .name = "Connor", .is_cool = true };
  Animal sharpie = { .name = "Sharpie", .specie = "Cat" };
  Animal gisele = { .name = "Gisele", .specie = "Rabbit" };
  connor.pets = { sharpie, gisele };

  Person amenda = { .age = 21, .name = "Amenda" };
  connor.friend = maybe::value(&amenda);

	// io::printn("Success");
 //  connor_json.print()!!;
	// io::printn("");
	//
  JsonValue? amenda_json = ser::serialize(&&json::serializer(), amenda);
  if (catch amenda_json) {
	  io::printn("error");
    return 0;
  }

	io::printn("Success");
  amenda_json.print()!!;
	io::printn("");

  JsonValue? connor_json = ser::serialize(&&json::serializer(), &connor);

  Person? p = des::deserialize{Person}(&&json::deserializer(connor_json));

  // p.print();
  // io::printn();

	return 0;
}


