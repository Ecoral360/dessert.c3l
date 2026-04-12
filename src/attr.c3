module dessert;

enum DessertEnum {
  NAME,
  ORDINAL,
  FIELD,
}

struct Dessert {
  bool skip;
  bool skip_if_empty;
  String rename;
  String[] aliases;
  String validator;
}

attrdef @Dessert(Dessert config) = @tag("dessert:ser", config), @tag("dessert:des", config);
attrdef @DessertSer(Dessert config) = @tag("dessert:ser", config);
attrdef @DessertDes(Dessert config) = @tag("dessert:des", config);

struct DessertEnumConfig {
  DessertEnum as;
  String field;
}
attrdef @DessertEnum(DessertEnumConfig config) = @tag("dessert:ser:enum", config), @tag("dessert:des:enum", config);
attrdef @DessertEnumSer(DessertEnumConfig config) = @tag("dessert:ser:enum", config);
attrdef @DessertEnumDes(DessertEnumConfig config) = @tag("dessert:des:enum", config);


struct DessertStructConfig {
  bool deny_unknown_fields;
}
attrdef @DessertStruct(DessertStructConfig config) = @tag("dessert:ser:struct", config), @tag("dessert:des:struct", config);
attrdef @DessertStructSer(DessertStructConfig config) = @tag("dessert:ser:struct", config);
attrdef @DessertStructDes(DessertStructConfig config) = @tag("dessert:des:struct", config);
