draw_set_font(fntNotoSans);

var _scale = 5;
var _incrY = 50 + _scale*2*string_height(" ");
var _x = 10;
var _y = 10;

var _string = "The quick brown fox\njumps over the lazy dog.";

draw_set_font(fntNotoSans);
draw_text_transformed(_x, _y, _string, _scale, _scale, 0);
draw_set_font(-1);

_y += _incrY;

draw_set_font(fntNotoSansSDF);
draw_text_transformed(_x, _y, _string, _scale, _scale, 0);
draw_set_font(-1);

_y += _incrY;

draw_set_font(fntNotoSansMSDF);
shader_set(shdScribbleToolMSDF);
draw_text_transformed(_x, _y, _string, _scale, _scale, 0);
draw_set_font(-1);
shader_reset();

draw_set_halign(fa_right);
draw_text(room_width-10, 10, "scaling factor = " + string(_scale) + "\nPress G to generate MSDF font data");
draw_set_halign(fa_left);