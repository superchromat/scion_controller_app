import 'package:flutter/material.dart';

enum AppAlertTone { success, error }

void showAppAlert(
  BuildContext context,
  String message, {
  AppAlertTone tone = AppAlertTone.success,
}) {
  final isError = tone == AppAlertTone.error;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      backgroundColor: Colors.transparent,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      duration: Duration(milliseconds: isError ? 4200 : 2600),
      content: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: const Color(0xFF2E2F34),
          border: Border.all(
            color: (isError
                    ? const Color(0xFFB56A77)
                    : const Color(0xFFF0D86A))
                .withValues(alpha: 0.55),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              size: 18,
              color:
                  isError ? const Color(0xFFE89AA7) : const Color(0xFFF0D86A),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'DINPro',
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.08,
                  color: Color(0xFFF1F1F3),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
