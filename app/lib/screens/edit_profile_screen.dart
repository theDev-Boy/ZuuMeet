import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../config/app_colors.dart';
import '../providers/auth_provider.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_textfield.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _ageCtrl;

  @override
  void initState() {
    super.initState();
    final user = context.read<AuthProvider>().userModel;
    _nameCtrl = TextEditingController(text: user?.name ?? '');
    _ageCtrl = TextEditingController(text: user?.age ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final auth = context.read<AuthProvider>();
    await auth.updateProfile(
      name: _nameCtrl.text.trim(),
      age: _ageCtrl.text.trim(),
    );
    if (!mounted) {
      return;
    }
    if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile updated.')),
    );
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              CustomTextField(
                hintText: 'Name',
                prefixIcon: Icons.person_outline,
                controller: _nameCtrl,
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Please enter your name'
                        : null,
              ),
              const SizedBox(height: 16),
              CustomTextField(
                hintText: 'Age',
                prefixIcon: Icons.cake_outlined,
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                validator: (value) =>
                    (value == null || value.trim().isEmpty)
                        ? 'Please enter your age'
                        : null,
              ),
              const SizedBox(height: 24),
              const Text(
                'You can update your name and age twice every 7 days.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
              const Spacer(),
              CustomButton(text: 'Save Changes', onPressed: _save),
            ],
          ),
        ),
      ),
    );
  }
}
