import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://nzpmyodqpxowncpbaoml.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im56cG15b2RxcHhvd25jcGJhb21sIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzEzMjY0OTUsImV4cCI6MjA4NjkwMjQ5NX0.-YiqTalaWDpN2xpHt3Ms7rbOPKnv1CXZ32Xud1oi8-8',
  );

  runApp(const AlignaApp());
}
