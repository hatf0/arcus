//$(function () {
  //  setNavigation();
//});

function setNavigation() {
    var path = window.location.pathname;
    path = path.replace(/\/$/, "");
    path = decodeURIComponent(path);

    $(".treeview-menu").each(function () {
        var currentChild = $(this).children();
        for(var i = 0; i < 100; i++) {
            if(typeof(currentChild) === "undefined") {
                return;
            }

            if(typeof(currentChild.attr('href')) === "undefined") {
            }
            else {
                var href = currentChild.attr('href');
                if(path.substring(0, href.length) === href) {
                    currentChild.parent().addClass('active');
                }
                return;
            }
            currentChild = currentChild.children();
        }
    });
}
