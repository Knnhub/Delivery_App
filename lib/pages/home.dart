import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE5E0FA), // พื้นหลังสี E5E0FA
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenHeight = constraints.maxHeight;
          final screenWidth = constraints.maxWidth;

          return Column(
            children: [
              SizedBox(height: screenHeight * 0.15),
              // รูป (วางกลางจอ)
              Center(
                child: Container(
                  width: screenWidth * 0.5, // กว้าง 50% ของจอ
                  height: screenWidth * 0.5,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    // color: Color.fromARGB(255, 78, 70, 70), // placeholder background
                    image: DecorationImage(
                      // --- แก้ไข path รูปภาพตรงนี้ ---
                      image: AssetImage('assets/images/welcome.jpg'),
                      // ---------------------------
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // ปุ่ม เข้าสู่ระบบ
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.15,
                  vertical: screenHeight * 0.01,
                ),
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/login'),
                  child: Container(
                    height: 57,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8C78E8),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Center(
                      child: Text(
                        'เข้าสู่ระบบ',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                          fontSize: 24,
                          color: Color(0xFFE5E0FA),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ปุ่ม สมัครสมาชิก
              Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: screenWidth * 0.15,
                  vertical: screenHeight * 0.01,
                ),
                child: GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/signup'),
                  child: Container(
                    height: 57,
                    decoration: BoxDecoration(
                      color: const Color(0xFF8C78E8),
                      borderRadius: BorderRadius.circular(50),
                    ),
                    child: const Center(
                      child: Text(
                        'สมัครสมาชิก',
                        style: TextStyle(
                          fontFamily: 'Inter',
                          fontWeight: FontWeight.w400,
                          fontSize: 24,
                          color: Color(0xFFE9D5FF),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              SizedBox(height: screenHeight * 0.05),
            ],
          );
        },
      ),
    );
  }
}
