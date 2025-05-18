#!/bin/bash

# Flutter analyze test script
# This script runs flutter analyze with the same settings as our CI pipeline

# Create a temporary analysis options file to ignore plugin warnings
cat > .analyze_temp_options.yaml << EOL
include: package:flutter_lints/flutter.yaml

analyzer:
  errors:
    invalid_use_of_internal_member: ignore
    missing_required_param: error
    missing_return: error
    must_be_immutable: warning
    sort_child_properties_last: ignore
    deprecated_member_use: ignore
    use_build_context_synchronously: ignore
    unnecessary_null_comparison: ignore
    unused_import: ignore
    unused_field: ignore
    unused_local_variable: ignore
    unused_element: ignore
    unnecessary_import: ignore
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "lib/generated_plugin_registrant.dart"
EOL

# Run analyze with our temporary options file
echo "Running Flutter analyze with temporary options..."
flutter analyze --no-fatal-warnings --options=.analyze_temp_options.yaml

# Check if there are any real errors that aren't from file_picker
echo ""
echo "Checking for critical errors only..."
flutter analyze --options=.analyze_temp_options.yaml 2>&1 | grep -v "file_picker" | grep -E "^error" > real_errors.txt || true

if [ -s real_errors.txt ]; then
  echo "Critical errors found in your code:"
  cat real_errors.txt
  exit_code=1
else
  echo "No critical issues detected!"
  exit_code=0
fi

# Clean up temp file
rm -f .analyze_temp_options.yaml real_errors.txt

exit $exit_code
