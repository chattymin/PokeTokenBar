import Foundation

/// The favorites: a graduated Pokémon liked on its Pokédex page, and the ♥ filter.
extension L {
    var favoriteAdd: String {
        t("즐겨찾기에 추가", "Add to favorites", "お気に入りに追加", "Añadir a favoritos", "Ajouter aux favoris",
          "Adicionar aos favoritos", "Zu Favoriten hinzufügen", "Добавить в избранное")
    }

    var favoriteRemove: String {
        t("즐겨찾기에서 빼기", "Remove from favorites", "お気に入りから外す", "Quitar de favoritos", "Retirer des favoris",
          "Remover dos favoritos", "Aus Favoriten entfernen", "Убрать из избранного")
    }

    var filterFavoritesOnly: String {
        t("즐겨찾기만", "Favorites only", "お気に入りのみ", "Solo favoritos", "Favoris uniquement", "Apenas favoritos",
          "Nur Favoriten", "Только избранное")
    }

    var favoriteLabel: String {
        t("즐겨찾기", "Favorite", "お気に入り", "Favorito", "Favori", "Favorito", "Favorit", "Избранное")
    }
}
