import 'package:flutter/material.dart';
import 'login_screen.dart';

class EmployeeLoginScreen extends StatelessWidget {
  const EmployeeLoginScreen({super.key});

  @override
  Widget build(BuildContext context) => const LoginScreen(useEmployeeId: true);
}
