import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_p2p/flutter_nfc_p2p.dart';
import 'package:http/http.dart' as http;

void main() => runApp(const NfcPaymentApp());

class NfcPaymentApp extends StatelessWidget {
  const NfcPaymentApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NFC P2P Payment',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.indigo,
        useMaterial3: true,
      ),
      home: const ModeSelectorScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode selector
// ---------------------------------------------------------------------------

class ModeSelectorScreen extends StatelessWidget {
  const ModeSelectorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NFC P2P Payment Demo')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ModeCard(
              icon: Icons.payment,
              label: 'Sender (Payer)',
              subtitle: 'Broadcast a payment token via HCE',
              color: Colors.indigo,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SenderScreen()),
              ),
            ),
            const SizedBox(height: 20),
            _ModeCard(
              icon: Icons.nfc,
              label: 'Receiver (Merchant)',
              subtitle: "Scan the payer's phone and submit to server",
              color: Colors.teal,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ReceiverScreen()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ModeCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 280,
      child: Card(
        elevation: 4,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  radius: 28,
                  child: Icon(icon, color: color, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(subtitle,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sender screen (Payer / HCE side)
// ---------------------------------------------------------------------------

class SenderScreen extends StatefulWidget {
  const SenderScreen({super.key});

  @override
  State<SenderScreen> createState() => _SenderScreenState();
}

class _SenderScreenState extends State<SenderScreen> {
  StreamSubscription<NfcEvent>? _sub;
  _SenderStatus _status = _SenderStatus.idle;
  String? _token;
  String? _errorMessage;

  static const String _mockToken = 'PAY-TOKEN-ABC123XYZ789';

  @override
  void dispose() {
    _sub?.cancel();
    FlutterNfcP2p.stopHce();
    super.dispose();
  }

  Future<void> _startBroadcasting() async {
    setState(() {
      _status = _SenderStatus.loading;
      _errorMessage = null;
    });

    // In a real app: fetch the token from your backend here.
    const token = _mockToken;

    _sub = FlutterNfcP2p.eventStream.listen(_handleEvent);

    try {
      await FlutterNfcP2p.startHce(token: token);
      setState(() {
        _token = token;
        _status = _SenderStatus.broadcasting;
      });
    } on UnsupportedError catch (e) {
      setState(() {
        _status = _SenderStatus.error;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _status = _SenderStatus.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _stopBroadcasting() async {
    await FlutterNfcP2p.stopHce();
    await _sub?.cancel();
    _sub = null;
    setState(() {
      _status = _SenderStatus.idle;
      _token = null;
    });
  }

  void _handleEvent(NfcEvent event) {
    switch (event) {
      case HceStartedEvent():
        setState(() => _status = _SenderStatus.broadcasting);
      case HceStoppedEvent():
        setState(() => _status = _SenderStatus.idle);
      case NfcErrorEvent(:final message):
        setState(() {
          _status = _SenderStatus.error;
          _errorMessage = message;
        });
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sender — Payer'),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusBanner(status: _status, errorMessage: _errorMessage),
            const SizedBox(height: 32),
            if (_status == _SenderStatus.broadcasting) ...[
              _InfoCard(
                icon: Icons.lock,
                label: 'Active Token',
                value: _token ?? '',
                color: Colors.indigo,
              ),
              const SizedBox(height: 16),
              const _PulsingNfcIcon(color: Colors.indigo),
              const SizedBox(height: 8),
              Text(
                'Hold this phone face-to-face with the merchant\'s phone.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            const Spacer(),
            if (_status != _SenderStatus.broadcasting)
              FilledButton.icon(
                onPressed: _status == _SenderStatus.loading
                    ? null
                    : _startBroadcasting,
                icon: const Icon(Icons.nfc),
                label: const Text('Start Broadcasting'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _stopBroadcasting,
                icon: const Icon(Icons.stop),
                label: const Text('Stop Broadcasting'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _SenderStatus { idle, loading, broadcasting, error }

// ---------------------------------------------------------------------------
// Receiver screen (Merchant / Reader side)
// ---------------------------------------------------------------------------

class ReceiverScreen extends StatefulWidget {
  const ReceiverScreen({super.key});

  @override
  State<ReceiverScreen> createState() => _ReceiverScreenState();
}

class _ReceiverScreenState extends State<ReceiverScreen> {
  StreamSubscription<NfcEvent>? _sub;
  _ReceiverStatus _status = _ReceiverStatus.idle;
  String? _receivedToken;
  String? _errorMessage;
  String? _serverResponse;
  bool _isSubmitting = false;

  final _amountController = TextEditingController();
  final _amountFocus = FocusNode();

  @override
  void dispose() {
    _sub?.cancel();
    FlutterNfcP2p.stopReader();
    _amountController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  String? get _requestedAmount {
    final text = _amountController.text.trim();
    return text.isEmpty ? null : text;
  }

  Future<void> _startListening() async {
    final amount = _requestedAmount;
    if (amount == null) {
      _amountFocus.requestFocus();
      return;
    }

    setState(() {
      _status = _ReceiverStatus.loading;
      _errorMessage = null;
      _receivedToken = null;
      _serverResponse = null;
    });

    _sub = FlutterNfcP2p.eventStream.listen(_handleEvent);

    try {
      await FlutterNfcP2p.startReader();
    } on UnsupportedError catch (e) {
      setState(() {
        _status = _ReceiverStatus.error;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _status = _ReceiverStatus.error;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _stopListening() async {
    await FlutterNfcP2p.stopReader();
    await _sub?.cancel();
    _sub = null;
    setState(() => _status = _ReceiverStatus.idle);
  }

  void _handleEvent(NfcEvent event) {
    switch (event) {
      case NfcListeningEvent():
        setState(() => _status = _ReceiverStatus.listening);
      case NfcDeviceDetectedEvent():
        setState(() => _status = _ReceiverStatus.reading);
      case NfcTokenReceivedEvent(:final token):
        setState(() {
          _status = _ReceiverStatus.received;
          _receivedToken = token;
        });
        _sub?.cancel();
      case NfcErrorEvent(:final message):
        setState(() {
          _status = _ReceiverStatus.error;
          _errorMessage = message;
        });
      default:
        break;
    }
  }

  Future<void> _submitToServer(String token) async {
    setState(() {
      _isSubmitting = true;
      _serverResponse = null;
    });

    final amount = _requestedAmount ?? '0';

    try {
      // Replace with your actual backend endpoint.
      final response = await http.post(
        Uri.parse('https://api.your-payment-backend.com/v1/transactions/redeem'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer YOUR_MERCHANT_TOKEN',
        },
        body: '{"payment_token": "$token", "amount": $amount}',
      );

      setState(() {
        _serverResponse = response.statusCode == 200
            ? 'Payment approved (${response.statusCode})'
            : 'Server returned ${response.statusCode}: ${response.body}';
      });
    } catch (e) {
      setState(() {
        _serverResponse = 'Network error: $e';
      });
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receiver — Merchant'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Amount entry — editable only before scanning starts
            TextField(
              controller: _amountController,
              focusNode: _amountFocus,
              enabled: _status == _ReceiverStatus.idle ||
                  _status == _ReceiverStatus.error,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: 'Amount to Request',
                hintText: '0.00',
                prefixIcon: const Icon(Icons.attach_money),
                border: const OutlineInputBorder(),
                suffixText: 'USD',
                errorText: _status == _ReceiverStatus.loading &&
                        _requestedAmount == null
                    ? 'Enter an amount'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            _StatusBanner(status: _status, errorMessage: _errorMessage),
            const SizedBox(height: 24),

            if (_status == _ReceiverStatus.listening) ...[
              const _PulsingNfcIcon(color: Colors.teal),
              const SizedBox(height: 8),
              Text(
                'Waiting for the payer\'s phone.\nAsk them to tap their device here.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],

            if (_status == _ReceiverStatus.reading) ...[
              const Center(child: CircularProgressIndicator()),
              const SizedBox(height: 8),
              const Text('Reading token…', textAlign: TextAlign.center),
            ],

            if (_status == _ReceiverStatus.received) ...[
              if (_requestedAmount != null) ...[
                _InfoCard(
                  icon: Icons.request_quote,
                  label: 'Requested Amount',
                  value: '\$$_requestedAmount',
                  color: Colors.teal,
                ),
                const SizedBox(height: 12),
              ],
              if (_receivedToken != null) ...[
                _InfoCard(
                  icon: Icons.check_circle,
                  label: 'Token Received',
                  value: _receivedToken!,
                  color: Colors.teal,
                ),
                const SizedBox(height: 12),
              ],
              if (_serverResponse != null)
                _InfoCard(
                  icon: Icons.cloud_done,
                  label: 'Server Response',
                  value: _serverResponse!,
                  color: Colors.green,
                ),
            ],

            const Spacer(),

            if (_status == _ReceiverStatus.received && _receivedToken != null)
              ...[
              FilledButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : () => _submitToServer(_receivedToken!),
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(_isSubmitting ? 'Submitting…' : 'Submit to Server'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => setState(() {
                  _status = _ReceiverStatus.idle;
                  _receivedToken = null;
                  _serverResponse = null;
                }),
                child: const Text('Scan Another'),
              ),
            ] else if (_status != _ReceiverStatus.listening &&
                _status != _ReceiverStatus.reading)
              FilledButton.icon(
                onPressed: _status == _ReceiverStatus.loading
                    ? null
                    : _startListening,
                icon: const Icon(Icons.nfc),
                label: const Text('Start Scanning'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.teal,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: _stopListening,
                icon: const Icon(Icons.stop),
                label: const Text('Stop Scanning'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _ReceiverStatus { idle, loading, listening, reading, received, error }

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------

class _StatusBanner extends StatelessWidget {
  final dynamic status;
  final String? errorMessage;

  const _StatusBanner({required this.status, this.errorMessage});

  @override
  Widget build(BuildContext context) {
    final (String label, Color color, IconData icon) = switch (status) {
      _SenderStatus.idle => ('Idle — tap to start broadcasting', Colors.grey, Icons.info_outline),
      _SenderStatus.loading => ('Starting HCE…', Colors.orange, Icons.hourglass_top),
      _SenderStatus.broadcasting => ('Broadcasting token', Colors.indigo, Icons.nfc),
      _SenderStatus.error => ('Error', Colors.red, Icons.error_outline),
      _ReceiverStatus.idle => ('Idle — tap to start scanning', Colors.grey, Icons.info_outline),
      _ReceiverStatus.loading => ('Enabling reader…', Colors.orange, Icons.hourglass_top),
      _ReceiverStatus.listening => ('Listening for devices…', Colors.teal, Icons.nfc),
      _ReceiverStatus.reading => ('Reading tag…', Colors.blue, Icons.sync),
      _ReceiverStatus.received => ('Token received!', Colors.green, Icons.check_circle),
      _ReceiverStatus.error => ('Error', Colors.red, Icons.error_outline),
      _ => ('Unknown', Colors.grey, Icons.help_outline),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: color, fontWeight: FontWeight.w600)),
                if (errorMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(errorMessage!,
                      style: const TextStyle(
                          color: Colors.red, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 12,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  SelectableText(
                    value,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PulsingNfcIcon extends StatefulWidget {
  final Color color;
  const _PulsingNfcIcon({required this.color});

  @override
  State<_PulsingNfcIcon> createState() => _PulsingNfcIconState();
}

class _PulsingNfcIconState extends State<_PulsingNfcIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransition(
        scale: _scale,
        child: Icon(Icons.nfc, size: 80, color: widget.color),
      ),
    );
  }
}
