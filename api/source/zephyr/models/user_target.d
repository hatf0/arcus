module zephyr.models.user_target;
import zephyr.models.base;

struct UserTarget
{
    mixin BaseModel;

    /* Creation/updating event */
    @serializationKeys("username") string username;
    @serializationKeys("email") string email;
    @serializationKeys("full_name") string realName;
    @serializationKeys("picture_url") string picture;
    @serializationKeys("admin_status") bool admin;

    /* Reset password */
    @serializationKeys("new_password") string newPassword = "";
}
