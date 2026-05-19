import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/api_config.dart';
import '../services/api_service.dart';
import '../theme/app_theme.dart';

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

  Timer? _refreshTimer;

  // API URL
  late TextEditingController _apiUrlController;
  bool _apiUrlSaved = false;

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
    _loadStatus();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadStatus());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _apiUrlController.dispose();
    _api.dispose();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final config = await _api.getMonitorConfig();
      if (mounted && config != null) {
        setState(() {
          _lastCheckAgo = '${config['last_check_ago_seconds']}s ago';
          _nextCheckIn = config['next_run_in_seconds'];
          _currentInterval = config['interval_seconds'];
        });
      }
    } catch (_) {}
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
        backgroundColor: AppColors.bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textSecondary),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      'Use http://10.0.2.2:8000 on emulator, http://<your-LAN-IP>:8000 on a device.',
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

              // ── Monitoring Frequency ──
              Text('Monitoring Frequency',
                  style: GoogleFonts.inter(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
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
                            Text("Applying...",
                                style: GoogleFonts.inter(color: AppColors.textSecondary)),
                          ],
                        )
                      : Text("Apply",
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

              const SizedBox(height: 24),

              // ── Monitor Status ──
              Text('Monitor Status',
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
                    _buildStatusRow('Last check', _lastCheckAgo, AppColors.textPrimary),
                    const Divider(height: 1, color: AppColors.border),
                    _buildStatusRow('Next check', 'in ${_nextCheckIn}s', AppColors.stateOk),
                    const Divider(height: 1, color: AppColors.border),
                    _buildStatusRow('Current interval', '${_currentInterval}s', AppColors.textPrimary),
                    const Divider(height: 1, color: AppColors.border),
                    _buildStatusRow('Auto-triggers (session)', '$_autoTriggerCount', AppColors.stateWarn),
                  ],
                ),
              ),
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
