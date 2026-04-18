export 'markdown_view_stub.dart'
    if (dart.library.html) 'markdown_view_web.dart'
    if (dart.library.io) 'markdown_view_native.dart';
