module bap.models.widget;

struct Widget
{
    enum : string
    {
        small_box = "small",
        info_box = "info"
    };

    enum colors : int
    {
        none,
        red,
        green,
        yellow,
        aqua,
        white
    };

    string widgetType;

    int xsmall;
    int small;
    int medium;
    int large;
    colors widgetColor;

    colors iconColor;

    string innerContent;

    string infoIcon;

    string box_id;

    string render()
    {
        import std.format;
        import std.conv;

        if (widgetType == info_box)
        {
            if (infoIcon != "")
            {
                if (iconColor != colors.none)
                {
                    innerContent = format!`
                <span class="info-box-icon bg-%s" id="%s-icon">
                  <i class="%s">
                  </i>
                </span>
                <div class="info-box-content" id="%s-content">
                  %s
              </div>
              `(to!string(iconColor),
                            box_id, infoIcon, box_id, innerContent);

                }
                else
                {
                    innerContent = format!`
                <span class="info-box-icon" id="%s-icon">
                  <i class="%s">
                  </i>
                </span>
                <div class="info-box-content" id="%s-content">
                  %s
              </div>
              `(box_id, infoIcon, box_id, innerContent);
                }
            }
        }
        string ret;

        if (widgetColor == colors.none)
        {
            ret = format!`
              <div class="col-xs-%d col-sm-%d col-md-%d col-lg-%d" style="filter: drop-shadow(0px 2px 5px rgba(0.0, 0.0, 0.0, 0.6));">
                <div class="%s-box" id="%s">
                    %s
                </div>
            </div>
          `(xsmall, small, medium, large,
                    widgetType, box_id, innerContent);
        }
        else
        {
            ret = format!`
              <div class="col-xs-%d col-sm-%d col-md-%d col-lg-%d" style="filter: drop-shadow(0px 2px 5px rgba(0.0, 0.0, 0.0, 0.6));">
                <div class="%s-box bg-%s" id="%s">
                    %s
                </div>
            </div>
          `(xsmall, small, medium, large, widgetType,
                    to!string(cast(colors) widgetColor), box_id, innerContent);

        }
        return ret;
    }

}
