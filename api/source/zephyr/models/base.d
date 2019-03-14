module zephyr.models.base;
public import asdf;

mixin template BaseModel() {
	string stringify() {
        import std.stdio : writeln;
        string ret = serializeToJson(this);
        writeln(ret);
        return ret;
	}
}
