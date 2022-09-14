import 'package:bg4102_software/constats/routes.dart';
import 'package:bg4102_software/service/auth/auth_service.dart';
import 'package:bg4102_software/view/Login_view.dart';
import 'package:bg4102_software/view/Register_view.dart';
import 'package:bg4102_software/view/Verify_email_view.dart';
import 'package:bg4102_software/view/forget_pw.dart';
import 'package:bg4102_software/view/note_view.dart';
import 'package:bg4102_software/view/profile_view.dart';
import 'package:flutter/material.dart';

void main() {
  //This is to connect device app to firebase server.
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
      // home: const HomePage(),
      home: const ProfileView(),
      theme: ThemeData(
        primaryColor: Colors.teal[900],
      ),
      routes: {
        loginRoute: (context) => const LoginView(),
        profileRoute: (context) => const ProfileView(),
        registerRoute: (context) => const RegisterView(),
        noteRoute: (context) => const NoteView(),
        verifyEmailRoute: (context) => const VerifyEmailView(),
        forgetPasswordRoute: (context) => const ForgetPasswordView(),

      },
    ),
  );
}

class HomePage extends StatelessWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: AuthService.firebase().initialize(),
      builder: (context, snapshot) {
        switch (snapshot.connectionState) {
          case ConnectionState.done:
            final user = AuthService.firebase().currentUser;
            if (user != null) {
              if (user.isEmailVerified) {
                return const NoteView();
              } else {
                return const VerifyEmailView();
              }
            } else {
              return const LoginView();
            }
          default:
            return const CircularProgressIndicator();
        }
      },
    );
  }
}
