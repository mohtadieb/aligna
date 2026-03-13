import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _brandGradient = LinearGradient(
    colors: [Color(0xFF7B5CF0), Color(0xFFE96BD2), Color(0xFFFFA96C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const _pageBg = Color(0xFFF8F5FF);
  static const _cardBorder = Color(0xFFF0EAFB);
  static const _primaryPurple = Color(0xFF6A42E8);
  static const _softPurple = Color(0xFFF8F5FF);
  static const _softPink = Color(0xFFFFF4FB);
  static const _softDanger = Color(0xFFFFF0F3);

  bool _deleting = false;
  bool _loggingOut = false;

  Future<void> _logout() async {
    if (_loggingOut) return;

    setState(() => _loggingOut = true);

    try {
      final supabase = Supabase.instance.client;
      await supabase.auth.signOut(scope: SignOutScope.local);

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Logged out')));

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Logout failed: $e')));
    } finally {
      if (mounted) setState(() => _loggingOut = false);
    }
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Log out'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Log out'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _logout();
    }
  }

  Future<void> _deleteAccount() async {
    if (_deleting) return;

    setState(() => _deleting = true);

    try {
      final supabase = Supabase.instance.client;

      await supabase.rpc('delete_my_account');
      await supabase.auth.signOut();

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Account deleted')));

      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete account: $e')));
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text('Delete account'),
          content: const Text(
            'This will permanently delete your account and associated data. This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _deleteAccount();
    }
  }

  Future<void> _openSupportEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@joinaligna.com',
      query: 'subject=Aligna Support',
    );

    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);

    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No email app found on this device.')),
      );
    }
  }

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse('https://joinaligna.com/privacy');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openTerms() async {
    final uri = Uri.parse('https://joinaligna.com/terms');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _pageBg,
      elevation: 0,
      scrolledUnderElevation: 0,
      title: Row(
        children: [
          Image.asset('assets/icon/aligna_inapp_icon.png', height: 28),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Settings',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: _brandGradient,
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7B5CF0).withOpacity(0.18),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Manage your\nAligna account',
            style: TextStyle(
              fontSize: 30,
              height: 1.08,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 10),
          Text(
            'Access support, legal information, and account actions in one place.',
            style: TextStyle(fontSize: 15, height: 1.45, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _settingsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback? onTap,
    Widget? trailing,
    Color? iconBg,
    Color? iconColor,
    Color? titleColor,
    Color? subtitleColor,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconBg ?? _softPurple,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: iconColor ?? _primaryPurple, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: titleColor ?? Colors.black87,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: subtitleColor ?? Colors.black54,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            trailing ??
                const Icon(Icons.chevron_right_rounded, color: Colors.black38),
          ],
        ),
      ),
    );
  }

  Widget _sectionCard({required String title, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: _cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _loadingIndicator() {
    return const SizedBox(
      width: 20,
      height: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _pageBg,
      appBar: _buildAppBar(),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _buildHeroCard(),
            const SizedBox(height: 18),
            _sectionCard(
              title: 'Support & legal',
              children: [
                _settingsTile(
                  icon: Icons.email_outlined,
                  title: 'Contact support',
                  subtitle: 'support@joinaligna.com',
                  onTap: _openSupportEmail,
                ),
                const SizedBox(height: 12),
                _settingsTile(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Privacy policy',
                  subtitle: 'Read how we handle your information.',
                  onTap: _openPrivacyPolicy,
                ),
                const SizedBox(height: 12),
                _settingsTile(
                  icon: Icons.description_outlined,
                  title: 'Terms of service',
                  subtitle: 'Review the terms for using Aligna.',
                  onTap: _openTerms,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _sectionCard(
              title: 'Account',
              children: [
                _settingsTile(
                  icon: Icons.logout_rounded,
                  title: 'Log out',
                  subtitle: 'Sign out from this device.',
                  onTap: _loggingOut ? null : _confirmLogout,
                  trailing: _loggingOut
                      ? _loadingIndicator()
                      : const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.black38,
                        ),
                ),
                const SizedBox(height: 12),
                _settingsTile(
                  icon: Icons.delete_outline_rounded,
                  title: 'Delete account',
                  subtitle: 'Permanently remove your account and data.',
                  onTap: _deleting ? null : _confirmDelete,
                  iconBg: _softDanger,
                  iconColor: Colors.red,
                  titleColor: Colors.red,
                  subtitleColor: Colors.red.shade300,
                  trailing: _deleting
                      ? _loadingIndicator()
                      : const Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.redAccent,
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
