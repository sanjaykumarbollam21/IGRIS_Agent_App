import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _secureStorage = const FlutterSecureStorage();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  String _gender = 'male'; // male, female, other
  bool _isLoading = true;
  bool _hasChanges = false;

  String _initFirst = '';
  String _initLast = '';
  String _initGender = 'male';

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _firstNameController.addListener(_checkChanges);
    _lastNameController.addListener(_checkChanges);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _checkChanges() {
    final changed = _firstNameController.text.trim() != _initFirst ||
        _lastNameController.text.trim() != _initLast ||
        _gender != _initGender;
    if (changed != _hasChanges) {
      setState(() => _hasChanges = changed);
    }
  }

  Future<void> _loadProfile() async {
    _initFirst = await _secureStorage.read(key: 'user_first_name') ?? '';
    _initLast = await _secureStorage.read(key: 'user_last_name') ?? '';
    _initGender = await _secureStorage.read(key: 'user_gender') ?? 'male';
    
    _firstNameController.text = _initFirst;
    _lastNameController.text = _initLast;
    _emailController.text = await _secureStorage.read(key: 'user_email') ?? '';
    _gender = _initGender;
    
    setState(() {
      _isLoading = false;
      _hasChanges = false;
    });
  }

  Future<void> _saveProfile() async {
    await _secureStorage.write(
        key: 'user_first_name', value: _firstNameController.text.trim());
    await _secureStorage.write(
        key: 'user_last_name', value: _lastNameController.text.trim());
    await _secureStorage.write(key: 'user_gender', value: _gender);

    _initFirst = _firstNameController.text.trim();
    _initLast = _lastNameController.text.trim();
    _initGender = _gender;

    setState(() => _hasChanges = false);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile saved'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          if (_hasChanges)
            TextButton(onPressed: _saveProfile, child: const Text('Save')),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 50,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.2),
                    child: Icon(Icons.person, size: 50,
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _firstNameController,
                    decoration: _inputDecor('First Name', Icons.person_outline),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _lastNameController,
                    decoration: _inputDecor('Last Name', Icons.person_outline),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _emailController,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Email',
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.05),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Gender selector
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.2),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Gender',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withValues(alpha: 0.6))),
                        const SizedBox(height: 4),
                        Text(
                          'IGRIS will address you as ${_gender == "male" ? "Sir" : _gender == "female" ? "Ma'am" : ""}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: Theme.of(context).colorScheme.primary),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _genderChip('Male', 'male', Icons.male),
                            const SizedBox(width: 8),
                            _genderChip('Female', 'female', Icons.female),
                            const SizedBox(width: 8),
                            _genderChip('Other', 'other', Icons.person),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _genderChip(String label, String value, IconData icon) {
    final selected = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _gender = value;
          _checkChanges();
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
                : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1),
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    fontSize: 12,
                  )),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecor(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
