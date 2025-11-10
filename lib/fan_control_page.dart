//fan_control_page.dart - 紅外線控制版本

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

// 風扇控制頁面
class FanControlPage extends StatefulWidget {
  final String jwtToken;
  const FanControlPage({super.key, required this.jwtToken});

  @override
  State<FanControlPage> createState() => _FanControlPageState();
}

class _FanControlPageState extends State<FanControlPage> {
  final String _baseUrl = 'http://localhost:3000/api';

  // 風扇狀態變數（本地狀態管理）
  bool _isFanOn = false;
  bool _isManualMode = true;
  int _fanSpeed = 0; // 1-8 級
  bool _isOscillationOn = false;
  bool _isVerticalSwingOn = false;
  bool _isDisplayOn = true;
  bool _isMuteOn = false;
  String _currentMode = 'normal';
  int _timerMinutes = 0;
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _fetchFanStatus();
    // 設定定時器,每隔5秒更新狀態
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchFanStatus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  // 獲取風扇狀態
  Future<void> _fetchFanStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fan/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
      );
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] && responseData['data'] != null) {
          final data = responseData['data'];
          setState(() {
            _isFanOn = data['is_on'] ?? false;
            _isManualMode = data['is_manual_mode'] ?? true;
            
            _fanSpeed = data['speed'] ?? 0;
            if (_fanSpeed < 0 || _fanSpeed > 8) _fanSpeed = 0;
            
            _isOscillationOn = data['is_oscillation_on'] ?? false;
            _isVerticalSwingOn = data['is_vertical_swing_on'] ?? false;
            _isDisplayOn = data['is_display_on'] ?? true;
            _isMuteOn = data['is_mute_on'] ?? false;
            _currentMode = data['mode'] ?? 'normal';
            _timerMinutes = data['timer_minutes'] ?? 0;
            _hasError = false;
            _errorMessage = '';
          });
        }
      } else if (response.statusCode == 401) {
        setState(() {
          _hasError = true;
          _errorMessage = '認證失效,請重新登入';
        });
      } else if (response.statusCode == 403) {
        setState(() {
          _hasError = true;
          _errorMessage = '權限不足,無法控制風扇';
        });
      } else {
        debugPrint('獲取風扇狀態失敗: ${response.statusCode} ${response.body}');
        setState(() {
          _hasError = true;
          _errorMessage = '無法獲取風扇狀態 (HTTP ${response.statusCode})';
        });
      }
    } catch (e) {
      debugPrint('無法獲取風扇狀態: $e');
      setState(() {
        _hasError = true;
        _errorMessage = '網路連線失敗,請檢查伺服器狀態';
      });
    }
  }

  // 發送紅外線控制指令
  Future<void> _sendIRCommand(String action) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ir-control'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
        body: jsonEncode({
          'device': 'fan',
          'action': action,
        }),
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success']) {
          _showSnackBar('${responseData['message'] ?? '指令發送成功'}');
          // 更新本地狀態
          _updateLocalState(action);
        } else {
          _showSnackBar('${responseData['message'] ?? '指令發送失敗'}', isError: true);
        }
      } else if (response.statusCode == 401) {
        _showSnackBar('認證失效,請重新登入', isError: true);
      } else if (response.statusCode == 403) {
        _showSnackBar('權限不足,無法控制風扇', isError: true);
      } else {
        final responseData = jsonDecode(response.body);
        _showSnackBar(responseData['message'] ?? '控制失敗', isError: true);
      }
    } catch (e) {
      debugPrint('發送紅外線指令失敗: $e');
      _showSnackBar('網路連線失敗,請檢查伺服器狀態', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 更新本地狀態（根據發送的指令）
  void _updateLocalState(String action) {
    setState(() {
      switch (action) {
        case 'power':
          _isFanOn = !_isFanOn;
          if (!_isFanOn) {
            _fanSpeed = 0;
          } else if (_fanSpeed == 0) {
            _fanSpeed = 1;
          }
          break;
        case 'speed_up':
          if (_isFanOn && _fanSpeed < 8) {
            _fanSpeed++;
          }
          break;
        case 'speed_down':
          if (_isFanOn && _fanSpeed > 1) {
            _fanSpeed--;
          }
          break;
        case 'swing_horizontal':
          _isOscillationOn = !_isOscillationOn;
          break;
        case 'swing_vertical':
          _isVerticalSwingOn = !_isVerticalSwingOn;
          break;
        case 'mode':
          // 循環切換模式: normal -> natural -> sleep -> eco
          final modes = ['normal', 'natural', 'sleep', 'eco'];
          final currentIndex = modes.indexOf(_currentMode);
          _currentMode = modes[(currentIndex + 1) % modes.length];
          break;
        case 'voice':
          _isMuteOn = !_isMuteOn;
          break;
        case 'timer':
          // Timer 指令會在彈窗中處理
          break;
        case 'light':
          _isDisplayOn = !_isDisplayOn;
          break;
      }
    });
  }

  // 更新手動/自動模式
  Future<void> _updateManualMode(bool value) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/fan/manual-mode'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
        body: jsonEncode({'isManualMode': value}),
      );
      
      if (response.statusCode == 200) {
        await _fetchFanStatus();
        _showSnackBar(value ? '已切換到手動模式' : '已切換到自動模式');
      } else {
        final responseData = jsonDecode(response.body);
        _showSnackBar(responseData['message'] ?? '更新模式失敗', isError: true);
      }
    } catch (e) {
      debugPrint('更新模式失敗: $e');
      _showSnackBar('網路連線錯誤', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: Duration(seconds: isError ? 4 : 2),
        ),
      );
    }
  }

  // 模式按鈕的 UI
  Widget _buildModeButton(String mode, String label) {
    bool isSelected = _isFanOn && _currentMode == mode;
    bool isDisabled = !_isManualMode;
    return ElevatedButton(
      onPressed: isDisabled || _isLoading ? null : () => _sendIRCommand('mode'),
      style: ElevatedButton.styleFrom(
        foregroundColor: isSelected ? Colors.white : (isDisabled ? Colors.grey : Colors.black),
        backgroundColor: isSelected ? Colors.blue : Colors.blueGrey,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      child: Text(label),
    );
  }

  // 建構功能按鈕的 Helper Widget
  Widget _buildFeatureButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
    bool isTimer = false,
  }) {
    return Column(
      children: [
        IconButton(
          onPressed: _isLoading ? null : onPressed,
          icon: Icon(
            icon,
            size: 40,
            color: isActive ? Colors.blue : Colors.black,
          ),
        ),
        Text(isTimer
             ? (_timerMinutes > 0 ? '定時 (${_timerMinutes}分)' : label)
             : label
        ),
      ],
    );
  }

  // 風速增減控制邏輯（使用紅外線指令）
  void _changeSpeed(bool isIncrement) {
    if (!_isManualMode) {
      _showSnackBar('請先切換到手動模式才能調整風速', isError: true);
      return;
    }
    
    // 如果風扇關閉,切換風速應先開啟並設定為 1 級
    if (!_isFanOn) {
      _sendIRCommand('power');
      return;
    }

    if (isIncrement) {
      if (_fanSpeed < 8) {
        _sendIRCommand('speed_up');
      }
    } else {
      if (_fanSpeed > 1) {
        _sendIRCommand('speed_down');
      }
    }
  }

  // 自動/手動模式控制區塊
  Widget _buildFanModeControl() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          '模式控制',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Row(
          children: [
            const Text(
              '自動',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Switch(
              value: _isManualMode,
              onChanged: _isLoading ? null : _updateManualMode,
              activeColor: Theme.of(context).primaryColor,
            ),
            const Text(
              '手動',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.blue;

    return Scaffold(
      body: _hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '連線失敗',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _fetchFanStatus,
                      child: const Text('重新連線'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 狀態顯示區塊
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            spreadRadius: 2,
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            _isFanOn ? '風扇狀態:開啟' : '風扇狀態:關閉',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: _isFanOn ? primaryColor : Colors.red
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _isManualMode ? '當前模式:手動' : '當前模式:自動 (一般風)',
                            style: TextStyle(
                              fontSize: 16,
                              color: _isManualMode ? Colors.black87 : Colors.orange
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '當前風速:${_isFanOn ? _fanSpeed : 0} 級 (Max 8)',
                            style: const TextStyle(fontSize: 18),
                          ),
                          if (_timerMinutes > 0) ...[
                            const SizedBox(height: 5),
                            Text(
                              '定時關機:${_timerMinutes} 分鐘',
                              style: const TextStyle(fontSize: 14, color: Colors.orange),
                            ),
                          ],
                          if (_isMuteOn) ...[
                            const SizedBox(height: 5),
                            const Text(
                              '提示音已關閉 (靜音)',
                              style: TextStyle(fontSize: 14, color: Colors.teal),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // 控制按鈕區塊
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            spreadRadius: 2,
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // 自動/手動模式控制
                          _buildFanModeControl(),
                          const SizedBox(height: 20),

                          // 電源按鈕
                          ElevatedButton(
                            onPressed: _isLoading ? null : () => _sendIRCommand('power'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isFanOn ? Colors.red : Colors.green,
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(20),
                            ),
                            child: Icon(
                              _isFanOn ? Icons.power_settings_new : Icons.power_off,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                          Text(_isFanOn ? '關閉' : '開啟'),
                          const SizedBox(height: 20),

                          // 風速控制 - 左右箭頭切換 1-8 級
                          const Text('風速控制 (1-8 級)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 減風速按鈕
                              IconButton(
                                icon: const Icon(Icons.arrow_left, size: 48),
                                onPressed: (_isLoading || !_isManualMode || _fanSpeed <= 1) 
                                  ? null 
                                  : () => _changeSpeed(false),
                                color: (_isManualMode && _fanSpeed > 1) ? primaryColor : Colors.grey,
                              ),

                              // 當前風速顯示
                              Container(
                                width: 80,
                                height: 80,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: primaryColor, width: 2),
                                ),
                                child: Text(
                                  '${_isFanOn ? _fanSpeed : 0}',
                                  style: TextStyle(
                                    fontSize: 36,
                                    fontWeight: FontWeight.bold,
                                    color: _isManualMode ? primaryColor : Colors.grey
                                  ),
                                ),
                              ),

                              // 加風速按鈕
                              IconButton(
                                icon: const Icon(Icons.arrow_right, size: 48),
                                onPressed: (_isLoading || !_isManualMode || _fanSpeed >= 8) 
                                  ? null 
                                  : () => _changeSpeed(true),
                                color: (_isManualMode && _fanSpeed < 8) ? primaryColor : Colors.grey,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // 擺頭、定時與顯示
                          const Text('擺頭、定時與顯示', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),

                          // 功能按鈕:左右擺頭、上下擺頭、靜音、顯示、定時
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                // 左右擺頭按鈕
                                _buildFeatureButton(
                                  icon: Icons.swap_horiz,
                                  label: '左右擺頭',
                                  isActive: _isOscillationOn,
                                  onPressed: () => _sendIRCommand('swing_horizontal'),
                                ),

                                const SizedBox(width: 16),

                                // 上下擺頭按鈕
                                _buildFeatureButton(
                                  icon: Icons.swap_vert,
                                  label: '上下擺頭',
                                  isActive: _isVerticalSwingOn,
                                  onPressed: () => _sendIRCommand('swing_vertical'),
                                ),

                                const SizedBox(width: 16),

                                // 液晶顯示按鈕
                                _buildFeatureButton(
                                  icon: _isDisplayOn ? Icons.remove_red_eye : Icons.visibility_off,
                                  label: '液晶顯示',
                                  isActive: _isDisplayOn,
                                  onPressed: () => _sendIRCommand('light'),
                                ),

                                const SizedBox(width: 16),

                                // 靜音按鈕
                                _buildFeatureButton(
                                  icon: _isMuteOn ? Icons.volume_off : Icons.volume_up,
                                  label: '靜音',
                                  isActive: _isMuteOn,
                                  onPressed: () => _sendIRCommand('voice'),
                                ),

                                const SizedBox(width: 16),

                                // 定時按鈕
                                _buildFeatureButton(
                                  icon: Icons.timer,
                                  label: '定時',
                                  isActive: _timerMinutes > 0,
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      builder: (context) => _buildTimerBottomSheet(),
                                    );
                                  },
                                  isTimer: true,
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // 模式控制 (風類)
                          const Text('風類切換', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildModeButton('normal', '一般風'),
                              _buildModeButton('natural', '自然風'),
                              _buildModeButton('sleep', '舒眠風'),
                              _buildModeButton('eco', 'ECO 溫控'),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 載入指示器
                    if (_isLoading) ...[
                      const SizedBox(height: 20),
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('處理中...'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // 定時器底部彈窗
  Widget _buildTimerBottomSheet() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('設定定時器', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTimerButton(60, '1 小時'),
              _buildTimerButton(120, '2 小時'),
              _buildTimerButton(180, '3 小時'),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              _sendIRCommand('timer');
              setState(() => _timerMinutes = 0);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('取消定時'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerButton(int minutes, String label) {
    return ElevatedButton(
      onPressed: () {
        _sendIRCommand('timer');
        setState(() => _timerMinutes = minutes);
        Navigator.pop(context);
      },
      style: ElevatedButton.styleFrom(
        foregroundColor: _timerMinutes == minutes ? Colors.white : Colors.black,
        backgroundColor: _timerMinutes == minutes ? Colors.blue : Colors.grey[200],
      ),
      child: Text(label),
    );
  }
}