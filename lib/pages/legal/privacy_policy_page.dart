import 'package:flutter/material.dart';

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    TextStyle? h1 = theme.textTheme.headlineMedium?.copyWith(
      fontWeight: FontWeight.bold,
    );

    TextStyle? h2 = theme.textTheme.titleLarge?.copyWith(
      fontWeight: FontWeight.bold,
    );

    TextStyle? h3 = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    TextStyle? body = theme.textTheme.bodyMedium?.copyWith(
      height: 1.7,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Privacy Policy'),
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
                  Text('Aligna Privacy Policy', style: h1),
                  const SizedBox(height: 16),
                  Text('Last updated: April 2, 2026', style: body),
                  const SizedBox(height: 32),

                  Text('1. Introduction', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Aligna (“we”, “our”, “us”) respects your privacy. '
                        'This Privacy Policy explains how we collect, use, and '
                        'protect your information when you use the Aligna mobile application.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'By using Aligna, you agree to the collection and use of '
                        'information in accordance with this policy.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('2. Information We Collect', style: h2),
                  const SizedBox(height: 16),

                  Text('Account Information', style: h3),
                  const SizedBox(height: 8),
                  _bulletList(
                    [
                      'Email address',
                      'Authentication data',
                    ],
                    body,
                  ),

                  const SizedBox(height: 16),
                  Text('User-Generated Content', style: h3),
                  const SizedBox(height: 8),
                  _bulletList(
                    [
                      'Questionnaire responses',
                      'Session data',
                      'AI-generated compatibility summaries',
                    ],
                    body,
                  ),

                  const SizedBox(height: 16),
                  Text('Purchase Information', style: h3),
                  const SizedBox(height: 8),
                  _bulletList(
                    [
                      'Purchase status (via Google Play)',
                      'Transaction verification data (handled securely by Google Play and RevenueCat)',
                    ],
                    body,
                  ),

                  const SizedBox(height: 12),
                  Text(
                    'We do not collect your payment card details directly.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('3. How We Use Your Information', style: h2),
                  const SizedBox(height: 8),
                  _bulletList(
                    [
                      'Provide compatibility insights',
                      'Generate AI summaries',
                      'Improve app functionality',
                      'Enable premium features',
                      'Ensure security and prevent fraud',
                    ],
                    body,
                  ),

                  const SizedBox(height: 32),
                  Text('4. AI Processing', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Aligna uses AI technology to generate relationship compatibility summaries.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'User responses may be processed securely through third-party AI services.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We do not sell your data.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('5. Data Storage', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Your data is securely stored using Supabase infrastructure.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'We implement reasonable security measures to protect your data.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('6. Third-Party Services', style: h2),
                  const SizedBox(height: 12),
                  Text('We use the following services:', style: body),
                  const SizedBox(height: 8),
                  _bulletList(
                    [
                      'Google Play (payments)',
                      'RevenueCat (purchase validation)',
                      'Google AI services (summary generation)',
                      'Supabase (backend services)',
                    ],
                    body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Each third-party service has its own privacy policy.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('7. Account Deletion', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Users can delete their account directly from within the Aligna app.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text('To delete your account:', style: body),
                  const SizedBox(height: 8),
                  _numberedList(
                    [
                      'Open the Aligna app',
                      'Log in',
                      'Go to Settings',
                      'Tap Delete account',
                    ],
                    body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This will permanently delete your account and associated personal data, '
                        'including profile data, questionnaire responses, session data, AI summaries, '
                        'and related account records.',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'If you cannot access the app, you can request deletion by contacting:',
                    style: body,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'support@joinaligna.com',
                    style: body?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Deletion requests are processed within 30 days.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('8. Children\'s Privacy', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'Aligna is not intended for users under the age of 18.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('9. Changes to This Policy', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'We may update this Privacy Policy from time to time. '
                        'Updates will be reflected on this page.',
                    style: body,
                  ),

                  const SizedBox(height: 32),
                  Text('10. Contact', style: h2),
                  const SizedBox(height: 12),
                  Text(
                    'If you have questions, contact us at:',
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

  Widget _numberedList(List<String> items, TextStyle? style) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        items.length,
            (index) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${index + 1}. ', style: style),
              Expanded(child: Text(items[index], style: style)),
            ],
          ),
        ),
      ),
    );
  }
}