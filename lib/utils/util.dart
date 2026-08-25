// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'dart:math';
import 'package:solvexo_pos/app/components/custom_bottom_sheet.dart';
import 'package:solvexo_pos/app/components/custom_divider.dart';
import 'package:solvexo_pos/app/components/custom_text.dart';
import 'package:solvexo_pos/config/resources/app_colors.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
// import 'package:url_launcher/url_launcher.dart';

class Util {
  static void hideKeyBoard(BuildContext context) {
    FocusScope.of(context).requestFocus(FocusNode());
  }

  static String deviceType() {
    return Platform.isIOS ? "ios" : "android";
  }

  // static Future<void> openUrl(String url) async {
  //   if (!await launchUrl(Uri.parse(url))) {
  //     throw Exception('Could not launch $url');
  //   }
  // }
  // static showCalenderDialogue(
  //   BuildContext context,
  //   Function(String) date, {
  //   DateTime? initialDate,
  // }) {
  //   showDialog(
  //     context: context,
  //     builder: (context) => CalendarDialog(
  //       initialDate: initialDate,
  //       onDateSelected: (selectedDate) {
  //         date(DateFormat('yyyy-MM-dd').format(selectedDate));
  //         print('Selected date: $selectedDate');
  //       },
  //     ),
  //   );
  // }

  static showCustomBottomSheet(
    context, {
    required Widget widget,
    required String title,
  }) {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      builder: (context) {
        return CustomBottomSheet(widget: widget, title: title);
      },
    );
  }

  static showCustomSuccessDialogue(context, {String? text}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        elevation: 0.4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 60),
        alignment: Alignment.center,
        backgroundColor: AppColors.white,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Center(
                child: CustomText(
                  text: "${"success".tr}!",
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CustomText(
                textAlign: TextAlign.center,
                text: text ?? "",
                fontSize: 14,
                fontWeight: FontWeight.w400,
              ),
            ),
            const CustomDivider(
              dividerColor: AppColors.textFieldBorderColor,
              bgColor: AppColors.white,
            ),
            GestureDetector(
              onTap: () {
                Get.back();
                Get.back();
              },
              child: Center(
                child: CustomText(
                  text: "okay".tr,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.appBarColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Future<String> selectTime(
    BuildContext context, {
    TimeOfDay? minTime,
  }) async {
    TimeOfDay? picked;
    bool isValid = false;

    while (!isValid) {
      picked = await showTimePicker(
        initialEntryMode: TimePickerEntryMode.dialOnly,
        context: context,
        initialTime: TimeOfDay.now(),
        builder: (BuildContext? context, Widget? child) {
          return Theme(
            data: ThemeData.light().copyWith(
              primaryColor: AppColors.appBarColor,
              hintColor: AppColors.appBarColor,
              colorScheme: const ColorScheme.light(
                primary: AppColors.appBarColor,
                surface: AppColors.white,
                onSurface: AppColors.black,
              ),
              buttonTheme: const ButtonThemeData(
                textTheme: ButtonTextTheme.primary,
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.appBarColor,
                ),
              ),
              timePickerTheme: TimePickerThemeData(
                dayPeriodColor: WidgetStateColor.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.appBarColor
                      : AppColors.white,
                ),
                dayPeriodTextColor: WidgetStateColor.resolveWith(
                  (states) => states.contains(WidgetState.selected)
                      ? AppColors.white
                      : AppColors.black,
                ),
                hourMinuteShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            child: MediaQuery(
              data: MediaQuery.of(
                context!,
              ).copyWith(alwaysUse24HourFormat: false),
              child: child!,
            ),
          );
        },
      );

      if (picked != null) {
        if (minTime == null ||
            (picked.hour > minTime.hour ||
                (picked.hour == minTime.hour &&
                    picked.minute >= minTime.minute))) {
          isValid = true;
        } else {
          await showDialog(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              title: CustomText(text: "invalid_time".tr, fontSize: 20),
              content: CustomText(
                text:
                    "${'please_select_a_time_later_than'.tr} ${minTime.format(context)}.",
                fontSize: 16,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: CustomText(
                    text: "okay".tr,
                    fontSize: 16,
                    color: AppColors.appBarColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }
      } else {
        return "";
      }
    }

    int hour = picked!.hour;
    String period = hour >= 12 ? "PM" : "AM";
    hour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    String formattedTime =
        "${hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')} $period";

    debugPrint("Selected Time: $formattedTime");
    return formattedTime;
  }

  static TimeOfDay? parseTimeOfDay(String formattedTime) {
    try {
      final RegExp timeRegex = RegExp(r'(\d{1,2}):(\d{2}) (AM|PM)');
      final Match? match = timeRegex.firstMatch(formattedTime);

      if (match != null) {
        int hour = int.parse(match.group(1)!);
        int minute = int.parse(match.group(2)!);
        String period = match.group(3)!;

        if (period == "PM" && hour != 12) {
          hour += 12;
        } else if (period == "AM" && hour == 12) {
          hour = 0;
        }

        return TimeOfDay(hour: hour, minute: minute);
      }
    } catch (e) {
      debugPrint("Error parsing time: $e");
    }
    return null; // Return null if parsing fails
  }

  static String getFileSizeString({required int bytes, int decimals = 0}) {
    const suffixes = ["bytes", "kb", "mb", "gb", "tb"];
    var i = (log(bytes) / log(1024)).floor();
    return ((bytes / pow(1024, i)).toStringAsFixed(decimals)) + suffixes[i];
  }

  static Future<File?> filePicker() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: ['jpg', 'pdf', 'doc', 'jpeg', 'png', 'txt', 'docx'],
    );

    if (result != null) {
      File file = File(result.files.single.path!);
      // Util().upload(file);
      debugPrint("File ${getFileSizeString(bytes: file.lengthSync())}");
      return file;
    } else {
      return null;

      // User canceled the picker
    }
  }
}
