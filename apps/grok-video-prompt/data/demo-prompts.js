// Demo prompts that fill each length to 10 styles, to lay out and try the page. Delete this file (and its
// <script> in ui/index.html) once the real prompts are in data/prompts.js.
(() => {
  const styles = [
    ["xoay-360", "Xoay 360° — Sản phẩm trên bệ xoay", "Máy quay đứng yên, [SẢN PHẨM] xoay chậm một vòng trên bệ tròn, nền trơn sáng, bóng đổ mềm."],
    ["dolly-in", "Dolly in — Tiến chậm vào chi tiết", "Máy quay tiến chậm từ toàn cảnh vào chi tiết nổi bật nhất của [SẢN PHẨM], lấy nét giữ trên sản phẩm."],
    ["anh-sang-sang", "Nắng sáng — Ánh sáng cửa sổ", "[SẢN PHẨM] trong phòng có nắng sáng chiếu qua cửa sổ, bóng nắng di chuyển nhẹ trên bề mặt."],
    ["lifestyle-gia-dinh", "Lifestyle — Không gian gia đình", "[SẢN PHẨM] đặt trong phòng khách ấm cúng, máy quay lia ngang chậm, đồ trang trí vừa phải, không người."],
    ["macro-chat-lieu", "Macro — Cận chất liệu", "Cận cảnh macro bề mặt và đường hoàn thiện của [SẢN PHẨM], ánh sáng xiên làm rõ vân và độ bóng."],
    ["top-down", "Top-down — Góc từ trên xuống", "Máy quay nhìn thẳng từ trên xuống [SẢN PHẨM], hạ dần độ cao, bố cục cân đối, nền gọn."],
    ["toi-gian-studio", "Studio tối giản — Nền một màu", "[SẢN PHẨM] trên nền studio một màu trung tính, ánh sáng ba điểm, máy quay trượt ngang chậm."],
    ["buoi-toi-am", "Buổi tối — Đèn vàng ấm", "[SẢN PHẨM] trong không gian buổi tối với đèn vàng ấm, máy quay đẩy nhẹ, không khí thư giãn."],
    ["chi-tiet-ket-cau", "Kết cấu — Các góc lắp ghép", "Lần lượt cận các mối nối, chân đế và phần lắp ghép của [SẢN PHẨM], chuyển cảnh mượt, giữ đúng tỉ lệ."],
    ["ngoai-troi", "Ngoài trời — Hiên nhà buổi chiều", "[SẢN PHẨM] đặt ở hiên nhà buổi chiều, gió nhẹ, ánh sáng tự nhiên, máy quay vòng nửa cung quanh sản phẩm."],
  ];
  for (const [seconds, list] of Object.entries(PROMPTS.durations)) {
    for (const [code, name, idea] of styles) {
      if (list.length >= 10) break;
      list.push({ code: `demo-${code}-${seconds}s`, name: `${name} (demo)`, prompt: `Tạo video giới thiệu [SẢN PHẨM] dài ${seconds} giây từ ảnh tham chiếu.\n\n${idea}\n\nGiữ đúng hình dáng, màu sắc và tỉ lệ của [SẢN PHẨM] trong ảnh; không thêm chữ, logo hay hiệu ứng biến hình.` });
    }
  }
})();
