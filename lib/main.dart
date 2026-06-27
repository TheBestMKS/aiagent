import 'package:flutter/material.dart';

import 'app/ai_agent_app.dart';

export 'app/ai_agent_app.dart';
export 'utils/path_utils.dart' show sanitizeFileName, truncateMiddle;

void main() {
  runApp(const AiAgentApp());
}
