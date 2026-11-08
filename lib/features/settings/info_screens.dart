import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_text.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../routing/app_router.dart';

class PrivacyNoticeScreen extends StatelessWidget {
  const PrivacyNoticeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: 'Privacy Notice',
      body: PageBody(
        children: [
          SoftCard(
            child: SelectableText(
              AppText.privacyNotice,
              style: context.text.bodyMedium?.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class DisclaimerScreen extends StatelessWidget {
  const DisclaimerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: 'Health Disclaimer',
      body: PageBody(
        children: [
          const SizedBox(height: 8),
          const Center(
            child: IconBubble(icon: Icons.health_and_safety_outlined, size: 72),
          ),
          const SizedBox(height: 16),
          SoftCard(
            child: Text(
              AppText.healthDisclaimer,
              style: context.text.bodyLarge?.copyWith(height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            tint: context.cycle.softLavenderCard,
            child: Text(AppText.fertileWarning, style: context.text.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: 'About CycleSync',
      body: PageBody(
        children: [
          const SizedBox(height: 8),
          const Center(child: AppLogo(size: 96)),
          const SizedBox(height: 12),
          Center(
            child: Text(AppText.appName, style: context.text.headlineSmall),
          ),
          Center(
            child: Text(
              'Version 1.0.0',
              style: context.text.bodySmall
                  ?.copyWith(color: context.cycle.muted),
            ),
          ),
          const SizedBox(height: 20),
          SoftCard(
            child: Text(AppText.healthDisclaimer,
                style: context.text.bodyMedium?.copyWith(height: 1.5)),
          ),
          const SectionTitle('Need someone to talk to?'),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                for (final (name, number) in AppText.helplines)
                  ListTile(
                    leading: const Icon(Icons.support_agent),
                    title: Text(name),
                    subtitle: SelectableText(number),
                  ),
              ],
            ),
          ),
          const SectionTitle('How estimates work'),
          for (final (title, body) in AppText.howEstimatesWork) ...[
            SoftCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: context.text.titleSmall),
                  const SizedBox(height: 4),
                  Text(body, style: context.text.bodyMedium),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          SoftCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.policy_outlined),
                  title: const Text('Privacy notice'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.privacy),
                ),
                const ListTile(
                  leading: Icon(Icons.gavel_outlined),
                  title: Text('Information Regulator (complaints)'),
                  subtitle: Text('inforeg.org.za'),
                ),
                ListTile(
                  leading: const Icon(Icons.report_outlined),
                  title: const Text('Report a privacy or security concern'),
                  subtitle: Text(AppText.supportEmail.isEmpty
                      ? 'Contact details will be published before launch'
                      : AppText.supportEmail),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Open-source licences'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: AppText.appName,
                    applicationVersion: '1.0.0',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
