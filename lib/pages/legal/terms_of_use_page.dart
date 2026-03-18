import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'privacy_policy_page.dart';

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    TextStyle? h1 = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );

    TextStyle? h2 = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.bold,
    );

    TextStyle? body = theme.textTheme.bodyMedium?.copyWith(
      height: 1.7,
    );

    final linkStyle = body?.copyWith(
      fontWeight: FontWeight.w600,
      decoration: TextDecoration.underline,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terms of Use'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aligna Terms of Service', style: h1),
                  const SizedBox(height: 16),
                  Text('Last updated: March 2026', style: body),
                  const SizedBox(height: 24),

                  Text(
                    'Welcome to Aligna. By accessing or using the Aligna mobile application '
                        '(\"the App\"), you agree to be bound by these Terms of Service.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'If you do not agree with these terms, please do not use the app.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('1. Description of the Service', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Aligna is a relationship compatibility app that allows users to create '
                        'shared sessions with a partner and answer guided questions. Based on '
                        'these responses, the app may generate AI-powered summaries intended to '
                        'provide insights into relationship compatibility.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'The app is provided for informational and entertainment purposes only.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('2. AI Generated Content', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Aligna uses artificial intelligence to generate compatibility summaries '
                        'and insights based on user responses.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text('These AI-generated summaries:', style: body),
                  const SizedBox(height: 8),
                  _bulletList(
                    [
                      'are automatically generated',
                      'may contain inaccuracies',
                      'should not be considered professional advice',
                    ],
                    body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Aligna does not provide psychological, relationship, legal, or medical advice.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Users should not rely solely on AI-generated insights when making important life decisions.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('3. User Accounts', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'To use certain features of the app, users must create an account.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text('Users are responsible for:', style: body),
                  const SizedBox(height: 8),
                  _bulletList(
                    [
                      'maintaining the confidentiality of their account',
                      'providing accurate information',
                      'all activities occurring under their account',
                    ],
                    body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Aligna reserves the right to suspend or terminate accounts that violate these terms.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('4. User Content', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Users may submit responses, answers, and other information through sessions within the app.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'By submitting content, users grant Aligna permission to process and analyze '
                        'this data for the purpose of providing app functionality and generating AI summaries.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Users remain responsible for the content they provide.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('5. Purchases and Subscriptions', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Some features of the app require a paid upgrade (\"Pro\").',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Purchases are processed through the app store provider (Google Play or Apple App Store). '
                        'All billing, refunds, and subscription management are handled by the respective app store '
                        'according to their policies.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Aligna does not directly process payment information.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('6. Account Deletion', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Users can delete their account directly from within the app by navigating to:',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Settings → Delete account',
                    style: body?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Deleting an account permanently removes associated personal data including '
                        'profile information, questionnaire responses, session data, and AI summaries.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Users may also request account deletion by contacting:',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'support@joinaligna.com',
                    style: body?.copyWith(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 32),
                  Text('7. Privacy', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Your privacy is important to us. Please review our Privacy Policy to understand '
                        'how we collect, use, and protect your information.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  RichText(
                    text: TextSpan(
                      style: body,
                      children: [
                        TextSpan(
                          text: 'View Privacy Policy',
                          style: linkStyle,
                          recognizer: TapGestureRecognizer()
                            ..onTap = () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const PrivacyPolicyPage(),
                                ),
                              );
                            },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                  Text('8. Limitation of Liability', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Aligna is provided \"as is\" without warranties of any kind.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'To the maximum extent permitted by law, the developers of Aligna are not responsible for:',
                    style: body,
                  ),
                  const SizedBox(height: 8),
                  _bulletList(
                    [
                      'decisions made based on AI-generated summaries',
                      'relationship outcomes',
                      'loss of data or service interruptions',
                    ],
                    body,
                  ),

                  const SizedBox(height: 32),
                  Text('9. Changes to These Terms', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'We may update these Terms of Service from time to time. '
                        'When we do, the updated version will be posted within the app or on our website.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Continued use of the app after changes constitutes acceptance of the updated terms.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('10. Contact', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'If you have any questions about these Terms of Service, you can contact us at:',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'support@joinaligna.com',
                    style: body?.copyWith(fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 48),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bulletList(List<String> items, TextStyle? style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: items
          .map(
            (item) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('• ', style: style),
              Expanded(child: Text(item, style: style)),
            ],
          ),
        ),
      )
          .toList(),
    );
  }
}