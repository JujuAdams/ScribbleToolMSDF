/// @param projectPath
/// @param fontName
/// @param sourceFontPath
/// @param [pathRelative=false]
/// @param [maxSize=2048]
/// @param [cleanUp=true]
/// @param [debug=false]

function ScribbleToolMSDF(_projectPath, _fontName, _sourceFontPath, _pathRelative = false, _maxSize = 2048, _cleanUp = true, _debug = false)
{
    static _repackBorder  = 2; //When repacking glyphs we should leave a little bit of an extra border to deal with edge cases
    static _dpiCorrection = 96/72; //GameMaker presumes 96 DPI (which is weird) but MSDFgen uses 72 DPI (which is standard)
    
    if (GM_build_type != "run")
    {
        show_error("Cannot run MSDF generator outside of the IDE\n ", true);
        return;
    }
    
    //First up, resolve a bunch of paths for different things
    var _projectDirectory = filename_dir(_projectPath) + "\\";
    var _msdfgenDirectory = _projectDirectory + "extensions\\ScribbleToolMSDFExtension\\";
    
    var _fontDirectory = _projectDirectory + "fonts\\" + _fontName + "\\";
    var _fontPNGPath   = _fontDirectory + _fontName + ".png";
    var _fontYYPath    = _fontDirectory + _fontName + ".yy";
    
    var _charsetPath    = _msdfgenDirectory + "charset.txt";
    var _batchfilePath  = _msdfgenDirectory + "generate.bat";
    var _tempFontPath   = _msdfgenDirectory + "font.ttf";
    var _outputPNGPath  = _msdfgenDirectory + "output.png";
    var _outputJSONPath = _msdfgenDirectory + "output.json";
    
    //Load up the font .yy and extra info
    var _buffer = buffer_load(_fontYYPath);
    var _originalYYString = buffer_read(_buffer, buffer_text);
    buffer_delete(_buffer);
    
    var _yyJSON = json_parse(_originalYYString);
    var _yyGlyphStruct = _yyJSON.glyphs;
    var _yySize        = _yyJSON.size;
    var _yySpread      = _yyJSON.sdfSpread;
    
    var _msdfSize   = floor(_yySize*_dpiCorrection);
    var _msdfSpread = floor(_yySpread*_dpiCorrection);
    
    //Export the glyphs in the .yy file to a charset file for consumption with MSDFgen
    var _charsetBuffer = buffer_create(1024, buffer_grow, 1);
    var _glyphNameArray = variable_struct_get_names(_yyGlyphStruct);
    var _i = 0;
    repeat(array_length(_glyphNameArray)-1)
    {
        buffer_write(_charsetBuffer, buffer_text, _glyphNameArray[_i]);
        buffer_write(_charsetBuffer, buffer_u8, 0x2C);
        ++_i;
    }
    
    //Write the last glyph without a comma and save out the charset
    buffer_write(_charsetBuffer, buffer_text, _glyphNameArray[_i]);
    buffer_save_ext(_charsetBuffer, _charsetPath, 0, buffer_tell(_charsetBuffer));
    buffer_delete(_charsetBuffer);
    
    //Copy the source font locally to the MSDFgen .exe
    //This makes the batch file simpler and more reliable
    if (_pathRelative) _sourceFontPath = _projectDirectory + _sourceFontPath;
    file_copy(_sourceFontPath, _msdfgenDirectory + "font.ttf");
    
    var _batchfileBuffer = buffer_create(1024, buffer_grow, 1);
    //msdf-atlas-gen.exe -type mtsdf -font Input/Montserrat-BoldItalic.ttf -size 24 -charset charset.txt -format png -imageout output.png -json output.json -pxrange 24
    buffer_write(_batchfileBuffer, buffer_text, "cd /D \"%~dp0\"\n");
    buffer_write(_batchfileBuffer, buffer_text, "msdf-atlas-gen.exe -type mtsdf -font font.ttf -size ");
    buffer_write(_batchfileBuffer, buffer_text, string(_msdfSize));
    buffer_write(_batchfileBuffer, buffer_text, " -charset charset.txt -format png -imageout output.png -json output.json -pxrange ");
    buffer_write(_batchfileBuffer, buffer_text, string(_msdfSpread));
    if (_debug) buffer_write(_batchfileBuffer, buffer_text, "\npause");
    buffer_save_ext(_batchfileBuffer, _batchfilePath, 0, buffer_tell(_batchfileBuffer));
    buffer_delete(_batchfileBuffer);
    
    //Make sure we have a blank state
    file_delete(_outputPNGPath);
    file_delete(_outputJSONPath);
    
    try
    {
        //Execute the batch file we just created
        execute_shell_simple(_batchfilePath);
    }
    catch(_error)
    {
        show_error("Failed to execute execute_shell_simple()\nIs this extension imported into the project?\n ", true);
        return;
    }
    
    var _time = current_time;
    while((not file_exists(_outputPNGPath)) || (not file_exists(_outputJSONPath)))
    {
        if (current_time - _time > 5000)
        {
            show_error("msdf-atlas-gen.exe failed to create expected files\n ", true);
            return;
        }
    }
    
    //Create substrings for the start and end of the original .yy file
    //The piece we're replacing in the middle is all the glyph definitions
    //We have to do this because GameMaker's JSON parser doesn't follow the basic JSON spec
    var _start = string_pos("  \"glyphs\": {", _originalYYString) + 13;
    var _end = string_pos_ext("  },", _originalYYString, _start);
    var _startString = string_copy(_originalYYString, 1, _start);
    var _endString = string_delete(_originalYYString, 1, _end);
    
    var _outputBuffer = buffer_create(2048, buffer_grow, 1);
    buffer_write(_outputBuffer, buffer_text, _startString);
    
    //Load up the new font JSON
    var _buffer = buffer_load(_outputJSONPath);
    var _jsonString = buffer_read(_buffer, buffer_text);
    buffer_delete(_buffer);
    
    var _msdfJSON = json_parse(_jsonString);;
    
    //Create a surface and sprite for recomposition
    var _sprite = sprite_add(_outputPNGPath, 1, false, false, 0, 0);
    var _spriteWidth  = sprite_get_width(_sprite);
    var _spriteHeight = sprite_get_height(_sprite);
    
    //Set up the surface for writing to
    var _surface = surface_create(_spriteWidth, _maxSize);
    surface_set_target(_surface);
    draw_clear_alpha(c_black, 0);
    
    //Make sure we overwrite everything and do some bilinear filtering as we go
    gpu_set_blendmode_ext(bm_one, bm_zero);
    var _oldTexFilter = gpu_get_tex_filter();
    gpu_set_tex_filter(true);
    
    var _lineX = _repackBorder;
    var _lineY = _repackBorder;
    
    //Define a function to write glyphs into the new .yy file
    var _funcWriteGlyph = function(_buffer, _character, _textureX, _textureY, _width, _height, _shift, _xOffset)
    {
        buffer_write(_buffer, buffer_text, "    \"");
        buffer_write(_buffer, buffer_text, string(_character));
        buffer_write(_buffer, buffer_text, "\": {\"character\":");
        buffer_write(_buffer, buffer_text, string(_character));
        buffer_write(_buffer, buffer_text, ",\"h\":");
        buffer_write(_buffer, buffer_text, string(_height));
        buffer_write(_buffer, buffer_text, ",\"offset\":");
        buffer_write(_buffer, buffer_text, string(_xOffset));
        buffer_write(_buffer, buffer_text, ",\"shift\":");
        buffer_write(_buffer, buffer_text, string(_shift));
        buffer_write(_buffer, buffer_text, ",\"w\":");
        buffer_write(_buffer, buffer_text, string(_width));
        buffer_write(_buffer, buffer_text, ",\"x\":");
        buffer_write(_buffer, buffer_text, string(_textureX));
        buffer_write(_buffer, buffer_text, ",\"y\":");
        buffer_write(_buffer, buffer_text, string(_textureY));
        buffer_write(_buffer, buffer_text, ",},\n");
    }
    
    //Start parsing!
    var _pointSize  = _msdfJSON.atlas.size;
    var _lineHeight = round(_pointSize*_msdfJSON.metrics.lineHeight);
    
    var _maxWidth  = 0;
    var _maxHeight = 0;
    
    var _topPadding = _dpiCorrection*_msdfSpread;
    
    //Iterate over all glyphs in the MSDF output
    var _glyphArray = _msdfJSON.glyphs;
    var _i = 0;
    repeat(array_length(_glyphArray))
    {
        var _glyphData = _glyphArray[_i];
        var _unicode = _glyphData.unicode;
        
        if (not variable_struct_exists(_glyphData, "atlasBounds")) //Whitespace character
        {
            var _shift = round(_pointSize*_glyphArray[0].advance);
            _funcWriteGlyph(_outputBuffer, _unicode, 0, 0, 0, _lineHeight, _shift, 0);
        }
        else
        {
            //Unpack the MSDFgen texture information into a format we can actually use
            //This atlas coordinate system is weird
            var _atlasData = _glyphData.atlasBounds;
            var _textureL = _atlasData.left - 0.5;
            var _textureT = _spriteHeight - _atlasData.top - 0.5;
            var _textureR = _atlasData.right - 0.5;
            var _textureB = _spriteHeight - _atlasData.bottom - 0.5;
            var _textureW = _textureR - _textureL
            var _textureH = _textureB - _textureT;
            
            var _planeData = _glyphData.planeBounds;
            var _xOffset = _pointSize*_planeData.left;
            var _yOffset = _pointSize - _pointSize*_planeData.top;
            var _shift   = round(_pointSize*_glyphData.advance);
            
            //Correct for x-axis offset
            var _xOffsetFrac = frac(_xOffset);
            var _xOffsetInt  = floor(_xOffset);
            var _xOffsetDraw = 0; //(_xOffset < 0)? (1 + _xOffsetFrac) : _xOffsetFrac;
            
            //Verrry basic texture packing
            //We wrap to the width of the original sprite since that's a useful guide
            if (_lineX + _textureW >= _spriteWidth)
            {
                _lineX = _repackBorder;
                _lineY += _lineHeight + _topPadding + 2*_repackBorder;
                _maxHeight = max(_maxHeight, _lineY);
            }
            
            //Copy the glyph from the MSDFgen texture sheet to our own
            //We do this so we can move glyphs to integer positions
            //GameMaker's .yy parser freaks out if there are decimals instead of integers
            draw_sprite_part(_sprite, 0, _textureL, _textureT, _textureW, _textureH, _lineX + _xOffsetDraw, _lineY + _topPadding + round(_yOffset));
            
            //MSDFGen puts a 1px border round the outside
            _funcWriteGlyph(_outputBuffer, _unicode, _lineX+1, _lineY+1, _textureW-2, _lineHeight-2 + _topPadding, _shift, _xOffsetInt + _msdfSpread);
            
            _lineX += _textureW + 2*_repackBorder;
            _maxWidth = max(_maxWidth, _lineX);
        }
        
        ++_i;
    }
    
    gpu_set_blendmode(bm_normal);
    gpu_set_tex_filter(_oldTexFilter);
    surface_reset_target();
    
    //Cap off the end of the new .yy file
    buffer_write(_outputBuffer, buffer_text, _endString);
    
    //Make a backup of the native GameMaker .yy file
    file_copy(_fontYYPath, filename_change_ext(filename_change_ext(_fontYYPath, "") + "_backup", ".yy"));
    
    //Save out the new .yy file
    buffer_save_ext(_outputBuffer, _fontYYPath, 0, buffer_tell(_outputBuffer));
    
    //Save out the new .png file
    _maxHeight += _lineHeight + _topPadding + _repackBorder;
    surface_save_part(_surface, _fontPNGPath, 0, 0, _maxWidth, _maxHeight);
    
    //Clean up temorary data
    buffer_delete(_outputBuffer);
    surface_free(_surface);
    sprite_delete(_sprite);
    
    //Finally, clean up any garbage we left on disk
    if (_cleanUp)
    {
        file_delete(_charsetPath);
        file_delete(_batchfilePath);
        file_delete(_tempFontPath);
        file_delete(_outputPNGPath);
        file_delete(_outputJSONPath);
    }
    
    show_debug_message("ScribbleToolMSDF success!");
}