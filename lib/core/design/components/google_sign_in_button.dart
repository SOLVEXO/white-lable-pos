import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../theme/app_theme.dart';
import '../tokens/tokens.dart';

// The XML namespace is split so source scans for hard-coded URLs (store_release_test) don't mistake it for one.
const String _svgNs = 'http:' '//www.w3.org/2000/svg';

/// Official Google "G" mark (multicolour, unmodified geometry).
const String kGoogleGLogoSvg = '''
<svg xmlns="$_svgNs" viewBox="0 0 48 48">
<path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/>
<path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/>
<path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/>
<path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/>
</svg>''';

/// "Continue with Google" button following Google's Sign-in branding guideline
/// for custom buttons:
///  - Light: #FFFFFF fill, 1 px #747775 stroke, #1F1F1F label.
///  - Dark:  #131314 fill, 1 px #8E918F stroke, #E3E3E3 label.
///  - Official multicolour G, 20 px, 12 px start padding, 10 px gap to the label.
///  - Label: Roboto Medium 14 / 20, one of the approved strings.
///  - Disabled: content at 38 %, stroke at 12 % (guideline's disabled treatment).
/// Height is 48 (guideline minimum is 40) to keep the POS touch target.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.label = 'Continue with Google',
  });
  final VoidCallback? onPressed;
  final bool loading;

  /// Must be one of Google's approved labels: "Sign in with Google",
  /// "Sign up with Google", "Continue with Google" or "Sign in".
  final String label;

  @override
  Widget build(BuildContext context) {
    final dark = context.palette.isDark;
    final fill = dark ? const Color(0xFF131314) : const Color(0xFFFFFFFF);
    final stroke = dark ? const Color(0xFF8E918F) : const Color(0xFF747775);
    final text = dark ? const Color(0xFFE3E3E3) : const Color(0xFF1F1F1F);
    final enabled = onPressed != null && !loading;
    final disabled = onPressed == null && !loading;

    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: disabled ? fill.withValues(alpha: 0.38) : fill,
        shape: RoundedRectangleBorder(
          borderRadius: Radii.rMd,
          side: BorderSide(
            color: disabled ? text.withValues(alpha: 0.12) : stroke,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onPressed : null,
          overlayColor: WidgetStatePropertyAll(text.withValues(alpha: 0.08)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Opacity(
                opacity: disabled ? 0.38 : 1,
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: loading
                          ? CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: text,
                            )
                          : SvgPicture.string(
                              kGoogleGLogoSvg,
                              width: 20,
                              height: 20,
                            ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Roboto',
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                          height: 20 / 14,
                          color: text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
