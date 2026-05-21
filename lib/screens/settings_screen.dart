import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

// Bundled app version — updated by CI on each release tag. Keep in sync
// with pubspec.yaml `version:` so the About section never lies.
const String kAppVersion = '0.1.0';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ApiService _api = ApiService();
  String _selectedPreset = '1 minute';
  int _customValue = 60;
  String _customUnit = 'seconds';
  bool _applying = false;
  String? _applySuccess;

  String _lastCheckAgo = '--';
  int _nextCheckIn = 0;
  int _currentInterval = 60;
  int _autoTriggerCount = 0;

  // Advanced settings are hidden by default so the screen reads like an
  // operator-facing preferences page, not a developer console.
  bool _advancedExpanded = false;

  Timer? _refreshTimer;

  // API URL
  late TextEditingController _apiUrlController;
  bool _apiUrlSaved = false;

  // API Key
  late TextEditingController _apiKeyController;
  bool _apiKeySaved = false;
  bool _apiKeyObscured = true;

  final List<Map<String, dynamic>> presets = [
    {'label': '30 seconds', 'seconds': 30},
    {'label': '1 minute', 'seconds': 60},
    {'label': '5 minutes', 'seconds': 300},
    {'label': '10 minutes', 'seconds': 600},
    {'label': '30 minutes', 'seconds': 1800},
    {'label': '1 hour', 'seconds': 3600},
    {'label': 'Custom', 'seconds': -1},
  ];

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController(text: ApiConfig.baseUrl);
    _apiKeyController = TextEditingController(text: ApiConfig.apiKey);
    _loadStatus();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final config = await _api.getMonitorConfig();
      final runs = await _api.getLatestRuns(50);
      if (mounted) {
        setState(() {
          if (config != null) {
            _lastCheckAgo = '${(config['last_check_ago_seconds'] as int? ?? 0)}s ago';
            _nextCheckIn = (config['next_run_in_seconds'] as int? ?? 0);
            _currentInterval = (config['interval_seconds'] as int? ?? 60);
            ApiConfig.updateFromMonitorConfig(config);
          }
          if (runs != null) {
            _autoTriggerCount = runs.where((r) => r['trigger_type'] == 'autonomous').length;
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    await ApiConfig.setApiKey(key);
    setState(() => _apiKeySaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _apiKeySaved = false);
    });
  }

  Future<void> _applyFrequency() async {
    int totalSeconds;
    if (_selectedPreset != 'Custom') {
      totalSeconds = presets.firstWhere((p) => p['label'] == _selectedPreset)['seconds'] as int;
    } else {
      int mult = _customUnit == 'minutes' ? 60 : _customUnit == 'hours' ? 3600 : 1;
      totalSeconds = _customValue * mult;
    }

    if (totalSeconds < 10 || totalSeconds > 86400) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimum 10 seconds, maximum 24 hours'), backgroundColor: AppColors.stateCritical),
      );
      return;
    }

    setState(() {
      _applying = true;
      _applySuccess = null;
    });

    final success = await _api.setMonitorConfig(totalSeconds);

    if (mounted) {
      setState(() {
        _applying = false;
        if (success) {
          _applySuccess = 'Monitoring interval set to ${totalSeconds}s — effective immediately';
          _loadStatus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to update monitor configuration'), backgroundColor: AppColors.stateCritical),
          );
        }
      });
    }
  }

  Future<void> _saveApiUrl() async {
    final url = _apiUrlController.text.trim();
    if (url.isEmpty) {
      await ApiConfig.clearBaseUrl();
    } else {
      final uri = Uri.tryParse(url);
      if (uri == null || !uri.hasScheme || (!uri.scheme.startsWith('http'))) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid URL — must start with http:// or https://'),
              backgroundColor: AppColors.stateCritical,
            ),
          );
        }
        return;
      }
      await ApiConfig.setBaseUrl(url);
    }
    setState(() => _apiUrlSaved = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _apiUrlSaved = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('Settings',
            style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600)),
        backgroundColor: AppColors.surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Monitoring Frequency (primary user-facing setting) ──
              Text('How often should StockSense check your business?',
                  style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                'StockSense scans your suppliers, sales, and inventory on this schedule and alerts you when something looks off.',
                style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedPreset,
                    dropdownColor: AppColors.surface,
                    style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
                    icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                    isExpanded: true,
                    onChanged: (val) => setState(() => _selectedPreset = val!),
                    items: presets
                        .map((p) => DropdownMenuItem(
                            value: p['label'] as String,
                            child: Text(p['label'] as String)))
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_selectedPreset == 'Custom') ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        style: GoogleFonts.inter(color: AppColors.textPrimary),
                        decoration: InputDecoration(
                          labelText: 'Value',
                          labelStyle: GoogleFonts.inter(color: AppColors.textSecondary),
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                              borderSide: const BorderSide(color: AppColors.border),
                              borderRadius: BorderRadius.circular(6)),
                          enabledBorder: OutlineInputBorder(
                              borderSide: const BorderSide(color: AppColors.border),
                              borderRadius: BorderRadius.circular(6)),
                        ),
                        onChanged: (v) => _customValue = int.tryParse(v) ?? 60,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(6)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _customUnit,
                          dropdownColor: AppColors.surface,
                          style: GoogleFonts.inter(color: AppColors.textPrimary, fontSize: 14),
                          icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                          onChanged: (v) => setState(() => _customUnit = v!),
                          items: ['seconds', 'minutes', 'hours']
                              .map((u) => DropdownMenuItem(value: u, child: Text(u)))
                              .toList(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _applying ? AppColors.surface2 : AppColors.actionPrimary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    elevation: 0,
                  ),
                  onPressed: _applying ? null : _applyFrequency,
                  child: _applying
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: AppColors.textSecondary)),
                            const SizedBox(width: 8),
                            Text("Saving…",
                                style: GoogleFonts.inter(color: AppColors.textSecondary)),
                          ],
                        )
                      : Text("Save schedule",
                          style: GoogleFonts.inter(fontWeight: FontWeight.w600, fontSize: 13)),
                ),
              ),
              if (_applySuccess != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: AppColors.tintOk,
                      border: Border.all(color: AppColors.stateOk),
                      borderRadius: BorderRadius.circular(6)),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: AppColors.stateOk, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(_applySuccess!,
                              style: GoogleFonts.inter(color: AppColors.stateOk, fontSize: 13))),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),

              // ── At a glance ──
              Text('At a glance',
                  style: GoogleFonts.inter(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    _buildStatusRow('Last check', _lastCheckAgo, AppColors.textPrimary),
                    const Divider(height: 1, color: AppColors.border),
                    _buildStatusRow('Next check', 'in ${_nextCheckIn}s', AppColors.stateOk),
                    const Divider(height: 1, color: AppColors.border),
                    _buildStatusRow('Total auto-alerts', '$_autoTriggerCount', AppColors.stateWarn),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // ── Advanced (collapsible) ──
              InkWell(
                onTap: () => setState(() => _advancedExpanded = !_advancedExpanded),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Icon(
                        _advancedExpanded
                            ? Icons.keyboard_arrow_down
                            : Icons.keyboard_arrow_right,
                        color: AppColors.textSecondary,
                        size: 20,
                      ),
                      const SizedBox(width: 4),
                      Text('Advanced',
                          style: GoogleFonts.inter(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Text('(for developers / IT)',
                          style: GoogleFonts.inter(
                              color: AppColors.textMuted, fontSize: 11)),
                    ],
                  ),
                ),
              ),
              if (!_advancedExpanded) const SizedBox(height: 12),
              if (_advancedExpanded) ...[
                const SizedBox(height: 8),
              // ── API URL Section ──
              Text('API URL',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _apiUrlController,
                      style: GoogleFonts.jetBrainsMono(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'http://10.0.2.2:8000',
                        hintStyle: GoogleFonts.jetBrainsMono(
                            color: AppColors.textMuted, fontSize: 13),
                        filled: true,
                        fillColor: AppColors.surface2,
                        border: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppColors.border),
                            borderRadius: BorderRadius.circular(6)),
                        enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppColors.border),
                            borderRadius: BorderRadius.circular(6)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppColors.actionPrimary),
                            borderRadius: BorderRadius.circular(6)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Emulator: http://10.0.2.2:8000  •  Device via USB (adb reverse): http://127.0.0.1:8000  •  Device via WiFi: http://<LAN-IP>:8000',
                      style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: _saveApiUrl,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.actionPrimary,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                              elevation: 0,
                            ),
                            child: Text('Save',
                                style: GoogleFonts.inter(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: () async {
                            await ApiConfig.clearBaseUrl();
                            setState(() {
                              _apiUrlController.text = ApiConfig.baseUrl;
                              _apiUrlSaved = true;
                            });
                            Future.delayed(const Duration(seconds: 2), () {
                              if (mounted) setState(() => _apiUrlSaved = false);
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          ),
                          child: Text('Reset',
                              style: GoogleFonts.inter(
                                  color: AppColors.textSecondary, fontSize: 13)),
                        ),
                      ],
                    ),
                    if (_apiUrlSaved) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppColors.stateOk, size: 14),
                          const SizedBox(width: 6),
                          Text('Saved — requests now route to ${ApiConfig.baseUrl}',
                              style: GoogleFonts.inter(color: AppColors.stateOk, fontSize: 11)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── API Key Section ──
              Text('API Key',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: _apiKeyController,
                      obscureText: _apiKeyObscured,
                      style: GoogleFonts.jetBrainsMono(
                          color: AppColors.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Leave empty if auth is disabled',
                        hintStyle: GoogleFonts.jetBrainsMono(
                            color: AppColors.textMuted, fontSize: 13),
                        filled: true,
                        fillColor: AppColors.surface2,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _apiKeyObscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                            size: 18,
                            color: AppColors.textMuted,
                          ),
                          onPressed: () => setState(() => _apiKeyObscured = !_apiKeyObscured),
                        ),
                        border: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppColors.border),
                            borderRadius: BorderRadius.circular(6)),
                        enabledBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppColors.border),
                            borderRadius: BorderRadius.circular(6)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: const BorderSide(color: AppColors.actionPrimary),
                            borderRadius: BorderRadius.circular(6)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Must match API_KEY in backend .env. Leave empty if auth is disabled.',
                      style: GoogleFonts.inter(color: AppColors.textMuted, fontSize: 11),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _saveApiKey,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.actionPrimary,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          elevation: 0,
                        ),
                        child: Text('Save',
                            style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600)),
                      ),
                    ),
                    if (_apiKeySaved) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.check_circle, color: AppColors.stateOk, size: 14),
                          const SizedBox(width: 6),
                          Text('API key saved',
                              style: GoogleFonts.inter(color: AppColors.stateOk, fontSize: 11)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // ── About ──
              Text('About',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8)),
                child: Column(
                  children: [
                    _buildStatusRow('App version', kAppVersion, AppColors.textPrimary),
                    const Divider(height: 1, color: AppColors.border),
                    _buildStatusRow('Server version', ApiConfig.serverVersion, AppColors.textPrimary),
                    const Divider(height: 1, color: AppColors.border),
                    _buildStatusRow('AI model', ApiConfig.geminiModel, AppColors.textPrimary),
                    const Divider(height: 1, color: AppColors.border),
                    _buildStatusRow('Current check interval', '${_currentInterval}s', AppColors.textPrimary),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Text(label, style: GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(value, style: GoogleFonts.inter(color: valueColor, fontSize: 13)),
        ],
      ),
    );
  }
}
