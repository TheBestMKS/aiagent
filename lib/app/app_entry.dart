import 'package:flutter/widgets.dart';

import 'ai_agent_app.dart'
    if (dart.library.html) 'ai_agent_web_app.dart' as implementation;

Widget buildAiAgentApp() => implementation.buildAiAgentApp();
