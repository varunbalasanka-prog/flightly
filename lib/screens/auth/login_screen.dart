import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../blocs/auth/auth_bloc.dart';

/// Login screen with Google Sign-In and email magic link.
/// Styled to match the Stitch dark dashboard aesthetic.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _emailController = TextEditingController();
  String? _emailError;

  /// Deliberately permissive -- just enough to stop an obviously malformed
  /// address making a pointless round trip and returning a raw API error.
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s.]+\.[^@\s]+$');
  static bool _isValidEmail(String value) => _emailPattern.hasMatch(value);

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: BlocConsumer<AuthBloc, AuthBlocState>(
        listener: (context, state) {
          if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: cs.error,
              ),
            );
          }
          if (state is AuthMagicLinkSent) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Magic link sent to ${state.email}'),
                backgroundColor: cs.primary,
              ),
            );
          }
        },
        builder: (context, state) {
          return Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  cs.surfaceContainerLowest,
                  cs.surfaceContainer,
                ],
              ),
            ),
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  // Without a cap the form stretched edge to edge on desktop
                  // and web, leaving inputs hundreds of pixels wide.
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: FadeTransition(
                    opacity: _fadeAnim,
                    child: SlideTransition(
                      position: _slideAnim,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── Logo / Branding ──
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  cs.primary,
                                  cs.primary.withValues(alpha: 0.7),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: cs.primary.withValues(alpha: 0.3),
                                  blurRadius: 24,
                                  offset: const Offset(0, 8),
                                ),
                              ],
                            ),
                            child: Icon(
                              Icons.flight_takeoff_rounded,
                              size: 40,
                              color: cs.onPrimary,
                            ),
                          ),
                          const SizedBox(height: 24),

                          Text(
                            'SkyPulse',
                            style: GoogleFonts.inter(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Live Flight Tracking · Private Beta',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w400,
                              color: cs.onSurfaceVariant,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 48),

                          // ── Google Sign-In Button ──
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: state is AuthLoading
                                  ? null
                                  : () => context
                                      .read<AuthBloc>()
                                      .add(AuthGoogleSignInRequested()),
                              // Image.network cannot decode SVG, so the remote
                              // Google mark always failed and silently fell
                              // back to a generic glyph -- plus it made a
                              // network request on every build of this screen.
                              icon: const _GoogleMark(size: 18),
                              label: Text(
                                state is AuthLoading
                                    ? 'Signing in...'
                                    : 'Continue with Google',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cs.surfaceContainerHigh,
                                foregroundColor: cs.onSurface,
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  side: BorderSide(
                                    color: cs.outline.withValues(alpha: 0.3),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          // ── Divider ──
                          Row(
                            children: [
                              Expanded(
                                child: Divider(
                                  color: cs.outline.withValues(alpha: 0.3),
                                ),
                              ),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                child: Text(
                                  'or',
                                  style: TextStyle(
                                    color: cs.onSurfaceVariant,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(
                                  color: cs.outline.withValues(alpha: 0.3),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),

                          // ── Email Magic Link ──
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: TextStyle(color: cs.onSurface),
                            onSubmitted: (_) => setState(() => _emailError = null),
                            decoration: InputDecoration(
                              hintText: 'Email address',
                              prefixIcon: const Icon(Icons.email_outlined),
                              errorText: _emailError,
                            ),
                          ),
                          const SizedBox(height: 16),

                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton(
                              onPressed: state is AuthLoading
                                  ? null
                                  : () {
                                      final email =
                                          _emailController.text.trim();
                                      if (!_isValidEmail(email)) {
                                        setState(() => _emailError = email.isEmpty
                                            ? 'Enter your email address'
                                            : 'Enter a valid email address');
                                        return;
                                      }
                                      setState(() => _emailError = null);
                                      context
                                          .read<AuthBloc>()
                                          .add(AuthMagicLinkRequested(email));
                                    },
                              child: const Text('Send Magic Link'),
                            ),
                          ),
                          const SizedBox(height: 32),

                          if (state is AuthMagicLinkSent)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: cs.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: cs.primary.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.check_circle_outline,
                                      color: cs.primary, size: 20),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Check your email for a sign-in link',
                                      style: TextStyle(
                                        color: cs.primary,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          const SizedBox(height: 48),
                          Text(
                            'v0.1.0-beta · 5-user private beta',
                            style: TextStyle(
                              color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The Google "G" drawn locally, so the sign-in button renders correctly
/// offline and without a network round trip.
class _GoogleMark extends StatelessWidget {
  final double size;
  const _GoogleMark({required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _GoogleMarkPainter()),
    );
  }
}

class _GoogleMarkPainter extends CustomPainter {
  static const _blue = Color(0xFF4285F4);
  static const _green = Color(0xFF34A853);
  static const _yellow = Color(0xFFFBBC05);
  static const _red = Color(0xFFEA4335);

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.22;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.butt;

    // Four quadrant arcs in Google's brand colours.
    canvas.drawArc(rect, -0.35, 1.22, false, paint..color = _red);
    canvas.drawArc(rect, 0.87, 1.40, false, paint..color = _yellow);
    canvas.drawArc(rect, 2.27, 1.40, false, paint..color = _green);
    canvas.drawArc(rect, 3.67, 1.75, false, paint..color = _blue);

    // The horizontal bar of the G.
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * 0.52,
        size.height * 0.41,
        size.width * 0.48 - stroke / 2,
        stroke,
      ),
      Paint()..color = _blue,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
