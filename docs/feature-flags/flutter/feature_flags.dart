// feature_flags.dart
const _defaults = <String, bool>{"checkout_new_ui_enabled": false};
bool isEnabled(String key) {
  // remoteConfig.getValue(key).boolValue 覆盖本地默认
  return remoteConfig.getBool(key) || _defaults[key] ?? false;
}
