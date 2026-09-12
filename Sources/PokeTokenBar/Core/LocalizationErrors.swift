import Foundation

extension L {
    // Resolve at display time so an existing error follows language changes.
    func userFacingError(_ error: any Error) -> String {
        let value = error as NSError
        if value.domain == NSURLErrorDomain {
            return t("네트워크 요청에 실패했습니다. 연결을 확인하고 다시 시도해 주세요.", "The network request failed. Check your connection and try again.", "通信に失敗しました。接続を確認して再試行してください。", "La solicitud de red falló. Comprueba la conexión e inténtalo de nuevo.", "La requête réseau a échoué. Vérifiez la connexion et réessayez.", "A solicitação de rede falhou. Verifique a conexão e tente novamente.", "Die Netzwerkanfrage ist fehlgeschlagen. Prüfe die Verbindung und versuche es erneut.")
        }
        if value.domain == NSCocoaErrorDomain {
            switch value.code {
            case NSFileReadNoPermissionError, NSFileWriteNoPermissionError:
                return t("파일 접근 권한이 없습니다. 권한이나 저장 위치를 확인해 주세요.", "File access was denied. Check permissions or choose another location.", "ファイルにアクセスできません。権限または保存先を確認してください。", "Acceso al archivo denegado. Revisa los permisos o elige otra ubicación.", "Accès au fichier refusé. Vérifiez les autorisations ou choisissez un autre emplacement.", "Acesso ao arquivo negado. Verifique as permissões ou escolha outro local.", "Dateizugriff verweigert. Prüfe die Berechtigungen oder wähle einen anderen Speicherort.")
            case NSFileWriteOutOfSpaceError:
                return t("저장 공간이 부족합니다. 공간을 확보하고 다시 시도해 주세요.", "There is not enough disk space. Free up space and try again.", "空き容量が不足しています。容量を確保して再試行してください。", "No hay espacio suficiente. Libera espacio e inténtalo de nuevo.", "L’espace disque est insuffisant. Libérez de l’espace et réessayez.", "Não há espaço suficiente. Libere espaço e tente novamente.", "Nicht genügend Speicherplatz. Gib Speicherplatz frei und versuche es erneut.")
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return t("파일을 찾을 수 없습니다. 위치를 확인하고 다시 선택해 주세요.", "The file could not be found. Check its location and select it again.", "ファイルが見つかりません。場所を確認して選び直してください。", "No se encontró el archivo. Comprueba su ubicación y selecciónalo de nuevo.", "Fichier introuvable. Vérifiez son emplacement et sélectionnez-le à nouveau.", "Arquivo não encontrado. Verifique o local e selecione novamente.", "Die Datei wurde nicht gefunden. Prüfe den Speicherort und wähle sie erneut aus.")
            default: break
            }
        }
        return t("작업을 완료하지 못했습니다. 다시 시도해 주세요.", "The operation could not be completed. Please try again.", "操作を完了できませんでした。再試行してください。", "No se pudo completar la operación. Inténtalo de nuevo.", "L’opération n’a pas pu être terminée. Veuillez réessayer.", "Não foi possível concluir a operação. Tente novamente.", "Der Vorgang konnte nicht abgeschlossen werden. Bitte versuche es erneut.")
    }

    var usageRefreshError: String {
        t("일부 사용량을 불러오지 못했습니다. 다시 새로고침해 주세요.", "Some usage could not be loaded. Please refresh again.", "一部の使用量を読み込めませんでした。再度更新してください。", "No se pudo cargar parte del uso. Actualiza de nuevo.", "Certaines données d’utilisation n’ont pas pu être chargées. Actualisez à nouveau.", "Não foi possível carregar parte do uso. Atualize novamente.", "Einige Nutzungsdaten konnten nicht geladen werden. Bitte aktualisiere erneut.")
    }

}
