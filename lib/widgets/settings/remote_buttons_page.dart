/*
 * ForkLauncher
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/l10n/app_localizations.dart';
import 'package:flauncher/providers/apps_service.dart';
import 'package:flauncher/widgets/settings/focusable_settings_tile.dart';
import 'package:flauncher/widgets/settings/settings_panel.dart';
import 'package:flauncher/widgets/settings/settings_theme.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Lets the user pick what a remote button opens. The buttons are caught by ButtonOverrideService,
/// an accessibility service the user has to turn on once.
class RemoteButtonsPage extends StatefulWidget {
  static const String routeName = "remote_buttons_panel";

  final FLauncherChannel channel;

  RemoteButtonsPage({super.key, FLauncherChannel? channel}) : channel = channel ?? FLauncherChannel();

  @override
  State<RemoteButtonsPage> createState() => _RemoteButtonsPageState();
}

class _RemoteButtonsPageState extends State<RemoteButtonsPage> with WidgetsBindingObserver {
  bool? _enabled;
  List<Map<String, dynamic>> _overrides = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _reload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // The user may come back from the accessibility settings with the service turned on.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _reload();
  }

  Future<void> _reload() async {
    final enabled = await widget.channel.isButtonOverrideServiceEnabled();
    final overrides = await widget.channel.getButtonOverrides();
    overrides.sort((a, b) => (a['keyCode'] as int).compareTo(b['keyCode'] as int));
    if (mounted) {
      setState(() {
        _enabled = enabled;
        _overrides = overrides;
      });
    }
  }

  Future<void> _addButton() async {
    final keyCode = await Navigator.of(context).push<int>(
      FastPageRoute(builder: (_) => _CaptureButtonPage(channel: widget.channel)),
    );
    if (keyCode == null || !mounted) return;
    await _chooseTarget(keyCode, isNew: true);
  }

  Future<void> _chooseTarget(int keyCode, {required bool isNew}) async {
    final choice = await Navigator.of(context).push<_Choice>(
      FastPageRoute(builder: (_) => _ChooseAppPage(keyCode: keyCode, canRemove: !isNew)),
    );
    if (choice == null) return;
    if (choice.remove) {
      await widget.channel.removeButtonOverride(keyCode);
    } else {
      await widget.channel.setButtonOverride(keyCode, choice.packageName);
    }
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final appsService = Provider.of<AppsService>(context);
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    return Column(
      children: [
        SettingsPageHeader(title: localizations.remoteButtons),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              if (_enabled == false) ...[
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(localizations.remoteButtonsServiceOff, style: textStyle),
                ),
                FocusableSettingsTile(
                  autofocus: true,
                  leading: const Icon(Icons.accessibility_new),
                  title: Text(localizations.openAccessibilitySettings, style: textStyle),
                  onPressed: () => widget.channel.openAccessibilitySettings(),
                ),
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: SelectableText(
                    'adb shell settings put secure enabled_accessibility_services '
                    'io.github.w4zzz4p.forklauncher/com.omeda.arc.ButtonOverrideService',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ),
                const SettingsSectionDivider(),
              ],
              if (_enabled == true)
                FocusableSettingsTile(
                  autofocus: true,
                  leading: const Icon(Icons.add),
                  title: Text(localizations.addRemoteButton, style: textStyle),
                  onPressed: _addButton,
                ),
              for (final item in _overrides)
                FocusableSettingsTile(
                  showChevron: true,
                  leading: const Icon(Icons.settings_remote),
                  title: Text(_buttonLabel(localizations, item['keyCode'] as int, item['keyName'] as String?),
                      style: textStyle),
                  subtitle: Text(_targetLabel(localizations, appsService, item['packageName'] as String? ?? '')),
                  onPressed: () => _chooseTarget(item['keyCode'] as int, isNew: false),
                ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(localizations.remoteButtonsHelp, style: Theme.of(context).textTheme.bodySmall),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "KEYCODE_PROG_RED" becomes "Prog red". Codes Android has no name for, like TCL's app buttons, show the number.
String _buttonLabel(AppLocalizations localizations, int keyCode, String? keyName) {
  if (keyName == null || !keyName.startsWith('KEYCODE_')) return localizations.remoteButtonNumber(keyCode);
  final words = keyName.substring('KEYCODE_'.length).replaceAll('_', ' ').toLowerCase();
  return words[0].toUpperCase() + words.substring(1);
}

String _targetLabel(AppLocalizations localizations, AppsService appsService, String packageName) {
  if (packageName.isEmpty) return localizations.remoteButtonDoNothing;
  for (final app in appsService.applications) {
    if (app.packageName == packageName) return app.name;
  }
  return packageName;
}

class _CaptureButtonPage extends StatefulWidget {
  final FLauncherChannel channel;

  const _CaptureButtonPage({required this.channel});

  @override
  State<_CaptureButtonPage> createState() => _CaptureButtonPageState();
}

class _CaptureButtonPageState extends State<_CaptureButtonPage> {
  bool _done = false;

  @override
  void initState() {
    super.initState();
    widget.channel.captureButton().then((keyCode) {
      _done = true;
      if (mounted) Navigator.of(context).pop(keyCode); // null: the service isn't running
    });
  }

  @override
  void dispose() {
    // Back pops this page while the service is still waiting for a button.
    if (!_done) widget.channel.cancelButtonCapture();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    return Column(
      children: [
        SettingsPageHeader(title: localizations.addRemoteButton),
        Expanded(
          child: Focus(
            autofocus: true,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.settings_remote, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      localizations.pressRemoteButton,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Choice {
  final String packageName;
  final bool remove;

  const _Choice(this.packageName, {this.remove = false});
}

class _ChooseAppPage extends StatelessWidget {
  final int keyCode;
  final bool canRemove;

  const _ChooseAppPage({required this.keyCode, required this.canRemove});

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context)!;
    final apps = Provider.of<AppsService>(context).applications;
    final textStyle = Theme.of(context).textTheme.bodyMedium;

    return Column(
      children: [
        SettingsPageHeader(title: localizations.remoteButtonOpens),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              if (canRemove)
                FocusableSettingsTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text(localizations.removeRemoteButton, style: textStyle),
                  onPressed: () => Navigator.of(context).pop(const _Choice('', remove: true)),
                ),
              FocusableSettingsTile(
                autofocus: true,
                leading: const Icon(Icons.block),
                title: Text(localizations.remoteButtonDoNothing, style: textStyle),
                onPressed: () => Navigator.of(context).pop(const _Choice('')),
              ),
              for (final app in apps)
                FocusableSettingsTile(
                  leading: const Icon(Icons.apps),
                  title: Text(app.name, style: textStyle),
                  onPressed: () => Navigator.of(context).pop(_Choice(app.packageName)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
