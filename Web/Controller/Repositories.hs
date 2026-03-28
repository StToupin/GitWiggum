module Web.Controller.Repositories where

import qualified Data.Text as Text
import IHP.QueryBuilder (filterWhereCaseInsensitive)
import IHP.ValidationSupport.Types (ValidatorResult (..), getValidationFailure)
import IHP.ValidationSupport.ValidateField (isSlug, nonEmpty, validateField, validateFieldIO)
import Web.Controller.Prelude
import Web.View.Repositories.New
import Web.View.Repositories.Show

instance Controller RepositoriesController where
    beforeAction = ensureIsUser

    action NewRepositoryAction =
        render NewView { repository = buildRepository currentUser "" "" "public" }

    action CreateRepositoryAction = do
        let name = paramOrDefault "" "name"
        let description = paramOrDefault "" "description"
        let visibility = paramOrDefault "public" "visibility"
        let repository = buildRepository currentUser name description visibility

        repositoryWithValidation <-
            repository
                |> validateField #name nonEmpty
                |> validateField #name isSlug
                |> validateFieldIO #name (validateRepositoryNameAvailable currentUser)

        if hasErrors repositoryWithValidation
            then render NewView { repository = repositoryWithValidation }
            else do
                createdRepository <- repositoryWithValidation |> createRecord
                redirectTo
                    ShowRepositoryAction
                        { ownerSlug = personalOwnerSlug currentUser
                        , repositoryName = get #name createdRepository
                        }

    action ShowRepositoryAction { ownerSlug, repositoryName } = do
        owner <-
            query @User
                |> filterWhere (#username, ownerSlug)
                |> fetchOne

        repository <-
            query @Repository
                |> filterWhere (#ownerUserId, get #id owner)
                |> filterWhere (#name, repositoryName)
                |> fetchOne

        render ShowView { owner, repository }

buildRepository :: User -> Text -> Text -> Text -> Repository
buildRepository currentUser name description visibility =
    newRecord @Repository
        |> set #ownerUserId (get #id currentUser)
        |> set #name (normalizeRepositoryName name)
        |> set #description (normalizeRepositoryDescription description)
        |> set #isPrivate (visibility == "private")

validateRepositoryNameAvailable ::
    (?modelContext :: ModelContext) =>
    User ->
    Text ->
    IO ValidatorResult
validateRepositoryNameAvailable currentUser repositoryName = do
    existingRepository <-
        query @Repository
            |> filterWhere (#ownerUserId, get #id currentUser)
            |> filterWhereCaseInsensitive (#name, repositoryName)
            |> fetchOneOrNothing

    pure $
        case existingRepository of
            Just _ -> Failure "This repository name is already in use for your namespace"
            Nothing -> Success

normalizeRepositoryName :: Text -> Text
normalizeRepositoryName = Text.toLower . Text.strip

normalizeRepositoryDescription :: Text -> Maybe Text
normalizeRepositoryDescription description =
    description
        |> Text.strip
        |> \value -> if Text.null value then Nothing else Just value

hasErrors :: Repository -> Bool
hasErrors repository =
    isJust (getValidationFailure #name repository)
