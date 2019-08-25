module zephyr.models.auth_info;
import zephyr.models.base;

struct AuthInfo {
	mixin BaseModel;
	@serializationKeys("user")
	string user;

	@serializationKeys("scope")
	string[] scopes;
}
