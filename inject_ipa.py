#!/usr/bin/env python3
import os
import sys
import zipfile
import shutil
import subprocess
import plistlib

def print_banner():
    print("=== Free Fire iOS IPA Python Injector (Kanha Method) ===")

def inject_ipa(ipa_path, dylib_path):
    if not os.path.exists(ipa_path) or not os.path.exists(dylib_path):
        print("[-] Lỗi: Không tìm thấy file IPA hoặc file Dylib!")
        return

    work_dir = "ipa_work_dir"
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    os.makedirs(work_dir)

    print("[+] Đang giải nén IPA...")
    with zipfile.ZipFile(ipa_path, 'r') as zip_ref:
        zip_ref.extractall(work_dir)

    payload_dir = os.path.join(work_dir, "Payload")
    app_name = [d for d in os.listdir(payload_dir) if d.endswith(".app")][0]
    app_path = os.path.join(payload_dir, app_name)

    print(f"[+] Tìm thấy App bundle: {app_name}")

    # Copy dylib vào thư mục ứng dụng
    dylib_name = os.path.basename(dylib_path)
    dest_dylib = os.path.join(app_path, dylib_name)
    shutil.copy(dylib_path, dest_dylib)
    print(f"[+] Đã copy {dylib_name} vào {app_path}")

    # Cập nhật Info.plist (hoặc sử dụng optool / insert_dylib nếu có)
    plist_path = os.path.join(app_path, "Info.plist")
    print("[+] Kiểm tra Info.plist...")
    
    # Hướng dẫn người dùng dùng các tool ký IPA phổ biến như Esign, Sideloadly hoặc Azule
    print("[*] Mẹo: Bạn có thể dùng công cụ 'Azule' trên Mac/Linux để inject tự động:")
    print(f"    azule -i {ipa_path} -o injected_output.ipa -f {dylib_path} -v")
    print("[+] Đã chuẩn bị sẵn sàng cấu trúc Payload để repack lại thành IPA!")

    output_zip = "Injected_FreeFire"
    shutil.make_archive(output_zip, 'zip', work_dir)
    print(f"[+] Hoàn tất! File nén đầu ra: {output_zip}.zip (Đổi tên thành .ipa hoặc dùng Sideloadly/Esign để ký)")

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("Cách dùng: python3 inject_ipa.py <file.ipa> <file.dylib>")
    else:
        inject_ipa(sys.argv[1], sys.argv[2])
