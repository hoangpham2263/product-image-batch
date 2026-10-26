# Translate known pipeline milestones into user-facing events. Unknown/raw diagnostics stay in log files.
function ConvertTo-UiEvent([string]$Line, [int]$CurrentIndex = 0) {
    $line = ($Line -replace '\x1b\[[0-9;]*m', '').Trim()
    if (-not $line) { return }
    $event = [pscustomobject]@{ Kind = ''; Text = ''; Stage = ''; Index = $CurrentIndex; Total = 0; Done = 0; Seconds = 0; Path = ''; QualityReason = '' }
    if ($line -match '\(#(\d+)\)\s*$') { $event.Index = [int]$Matches[1] }
    if ($line -match '^Starting: (\d+) URLs') {
        $event.Kind = 'Start'; $event.Total = [int]$Matches[1]
        $event.Text = "Bắt đầu xử lý $($event.Total) sản phẩm."
    } elseif ($line -match '^\[(\d+)/(\d+)\] ') {
        $event.Kind = 'Item'; $event.Index = [int]$Matches[1]; $event.Total = [int]$Matches[2]; $event.Stage = 'Đang chuẩn bị'
    } elseif ($line -match '^Batch:\s*(.+)') {
        $event.Kind = 'Output'; $event.Path = $Matches[1].Trim()
    } elseif ($line -match '^Missing data: (\d+)') {
        $event.Kind = 'Info'
        $event.Text = "Có $($Matches[1]) sản phẩm thiếu ảnh mẫu. Gửi file missing-data.csv và thư mục missing-data trong kết quả để bổ sung dữ liệu."
    } elseif ($line -match '^\[PRODUCT\]') {
        $event.Kind = 'Stage'; $event.Stage = 'Đang chuẩn bị'
    } elseif ($line -match '^\[CLASSIFY\]') {
        $event.Kind = 'Stage'; $event.Stage = 'Đang nhận diện sản phẩm'
    } elseif ($line -match '^\[REFERENCE-COUNT\] Using (\d+)') {
        $event.Kind = 'Stage'; $event.Stage = 'Đã chọn ảnh mẫu phù hợp'
        $event.Text = "Sản phẩm $($event.Index): dùng $($Matches[1]) ảnh mẫu đã kiểm tra và bối cảnh thật trong ảnh."
    } elseif ($line -match '^\[SELECT\] Subject') {
        $event.Kind = 'Stage'; $event.Stage = 'Đang chọn người mẫu'
    } elseif ($line -match '^\[SELECT\] Scene') {
        $event.Kind = 'Stage'; $event.Stage = 'Đang chọn bối cảnh'
    } elseif ($line -match '^\[IMAGE\]') {
        $event.Kind = 'Stage'; $event.Stage = 'Đang tạo ảnh'
        $event.Text = "Sản phẩm $($event.Index): đang tạo ảnh."
    } elseif ($line -match '^\[HUMAN-APPROVED\]') {
        $event.Kind='Stage';$event.Stage='Đang bàn giao ảnh đã duyệt'
        $event.Text="Sản phẩm $($event.Index): bạn đã duyệt ảnh. Đang lưu ảnh và CSV; không tạo ảnh lại."
    } elseif ($line -match '^WARNING: Approved image saved; review text unavailable') {
        $event.Kind='Info';$event.Text='Ảnh đã lưu. Chưa tạo được nội dung đánh giá; ô nội dung trong CSV để trống để bạn điền.'
    } elseif ($line -match '^\[REVIEW\]') {
        $event.Kind = 'Stage'; $event.Stage = 'Đang viết đánh giá'
        $event.Text = "Sản phẩm $($event.Index): đang viết đánh giá."
    } elseif ($line -match '^\[QUALITY\]') {
        $event.Kind = 'Stage'; $event.Stage = 'Đang kiểm tra kết quả'
    } elseif ($line -match '^\[REFINE\]') {
        $event.Kind = 'Stage'; $event.Stage = 'Đang hoàn thiện ảnh'
        $event.Text = "Sản phẩm $($event.Index): đang hoàn thiện ảnh cho phù hợp hơn."
    } elseif ($line -match '^\[QUALITY-REASON\]\s*(?:FAIL:\s*)?(.+)') {
        $event.Kind = 'QualityReason'
        $reason = ($Matches[1] -replace '\s*\(#\d+\)\s*$','').Trim()
        $event.QualityReason = $reason
        $event.Text = "Sản phẩm $($event.Index): lý do cần sửa ảnh: $reason"
    } elseif ($line -match '^\[DOWNLOAD-RETRY\]') {
        $event.Kind = 'Retry'; $event.Stage = 'Đang thử tải lại sản phẩm'
        $event.Text = "Sản phẩm $($event.Index): trang hoặc ảnh phản hồi chậm. Đang tự thử tải lại."
    } elseif ($line -match '^\[AI-CONNECTION\]') {
        $event.Kind = 'Retry'; $event.Stage = 'Kết nối gián đoạn'
        $event.Text = 'Kết nối AI bị gián đoạn. Đang chờ phục hồi; lượt này sẽ dừng nếu không kết nối lại được trong 60 giây.'
    } elseif ($line -match '^\[AI-RESUMED\]') {
        $event.Kind = 'Retry'; $event.Stage = 'AI đã phản hồi trở lại'
        $event.Text = 'AI đã phản hồi trở lại. Đang tiếp tục xử lý.'
    } elseif ($line -match '^\[AI-WAIT\] (\d+)/(\d+)s') {
        $event.Kind = 'Stage'; $event.Stage = "Đang chờ AI $($Matches[1])/$($Matches[2]) giây"
    } elseif ($line -match '^\[RETRY\]') {
        $event.Kind = 'Retry'; $event.Stage = 'Đang chờ dịch vụ'
        $event.Text = 'Dịch vụ đang bận. Ứng dụng sẽ tự thử lại.'
    } elseif ($line -match '^\[METADATA\]') {
        $event.Kind = 'Saving'; $event.Stage = 'Đang lưu kết quả'
    } elseif ($line -match '^\[OK\]') {
        if ($line -match '\[ITEM (\d+)\]') { $event.Index = [int]$Matches[1] }
        $event.Kind = 'Completed'; $event.Stage = 'Đã xong'
        $event.Text = "Sản phẩm $($event.Index) đã hoàn tất."
    } elseif ($line -match '^WARNING:\s*(?:\[ITEM (\d+)\]\s*)?Failed;') {
        if ($Matches[1]) { $event.Index = [int]$Matches[1] }
        $event.Kind = 'Failed'; $event.Stage = 'Chưa hoàn tất'
        $event.Text = "Sản phẩm $($event.Index) chưa hoàn tất. Link được giữ lại để thử lại."
        if ($line -match '\[CAUSE:PRODUCT_TIMEOUT\]') {
            $event.Text = "Sản phẩm $($event.Index): trang hoặc ảnh phản hồi quá chậm sau 3 lần thử. Link được giữ lại để chạy lại."
        } elseif ($line -match '\[CAUSE:PRODUCT_NETWORK\]') {
            $event.Text = "Sản phẩm $($event.Index): chưa kết nối được trang hoặc ảnh sau 3 lần thử. Kiểm tra mạng rồi chạy lại."
        } elseif ($line -match '\[CAUSE:PRODUCT_ACCESS\]') {
            $event.Text = "Sản phẩm $($event.Index): trang hoặc ảnh yêu cầu đăng nhập hoặc đang chặn truy cập. Vui lòng dùng link công khai."
        } elseif ($line -match '\[CAUSE:PRODUCT_NOT_FOUND\]') {
            $event.Text = "Sản phẩm $($event.Index): không tìm thấy trang hoặc ảnh sản phẩm. Vui lòng kiểm tra link."
        } elseif ($line -match '\[CAUSE:MISSING_DATA\]') {
            $event.Text = "Sản phẩm $($event.Index): thiếu ảnh mẫu cho loại sản phẩm này. Đã ghi vào missing-data trong kết quả."
        } elseif ($line -match '\[CAUSE:PRODUCT_DOWNLOAD\]') {
            $event.Text = "Sản phẩm $($event.Index): chưa tải được trang hoặc ảnh. Link được giữ lại để thử lại."
        } elseif ($line -match '\[CAUSE:STORE_LOCKED\]') {
            $event.Text = "Sản phẩm $($event.Index): cửa hàng đang bật mật khẩu. Tắt mật khẩu cửa hàng hoặc dùng link công khai rồi thử lại."
        } elseif ($line -match '\[CAUSE:AUTH\]') {
            $event.Text = 'Không xác thực được tài khoản. Bấm Kiểm tra ChatGPT để xem hướng dẫn đăng nhập.'
        } elseif ($line -match '\[CAUSE:QUOTA\]') {
            $event.Text = 'Tài khoản đã hết hạn mức. Kiểm tra tài khoản hoặc chờ hạn mức được cấp lại.'
        } elseif ($line -match '\[CAUSE:AI_TIMEOUT\]') {
            $event.Text = 'AI phản hồi quá thời gian chờ. Đã dừng lượt xử lý; link được giữ lại để thử lại.'
        } elseif ($line -match '\[CAUSE:NETWORK\]') {
            $event.Text = 'Kết nối bị gián đoạn. Kiểm tra Internet rồi chạy lại các link còn lại.'
        } elseif ($line -match '\[CAUSE:BUSY\]') {
            $event.Text = 'Dịch vụ vẫn đang bận. Vui lòng thử lại sau.'
        } elseif ($line -match 'No product reference found|Invalid reference image URL') {
            $event.Text = "Sản phẩm $($event.Index): không đọc được ảnh sản phẩm. Vui lòng kiểm tra link."
        } elseif ($line -match 'Image quality check failed|Invalid image quality response') {
            $event.Text = "Sản phẩm $($event.Index): ảnh chưa đạt yêu cầu. Link được giữ lại để thử lại."
            if ($line -match 'Image quality check failed:\s*(?:FAIL:\s*)?(.+)$') {
                $event.Text += " Lý do: $($Matches[1].Trim())"
            }
        } elseif ($line -match 'No suitable real scene reference|No suitable source photo found') {
            $event.Text = "Sản phẩm $($event.Index): chưa tìm được ảnh mẫu thực tế phù hợp. Link được giữ lại."
        }
    } elseif ($line -match '^Done: (\d+)/(\d+) exported in (\d+)s') {
        $event.Kind = 'Summary'; $event.Done = [int]$Matches[1]; $event.Total = [int]$Matches[2]; $event.Seconds = [int]$Matches[3]
        $event.Text = "Đã hoàn tất $($event.Done)/$($event.Total) sản phẩm."
    } elseif ($line -match '^WARNING: Invalid') {
        $event.Kind = 'Warning'; $event.Text = 'Có link không hợp lệ. Vui lòng kiểm tra lại danh sách.'
    } elseif ($line -match '^No product URLs') {
        $event.Kind = 'Warning'; $event.Text = 'Chưa có link sản phẩm để xử lý.'
    }
    if ($event.Kind) { return $event }
}
