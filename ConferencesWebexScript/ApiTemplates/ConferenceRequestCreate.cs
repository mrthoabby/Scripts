using ConferencesWebexScript.Entities;
using ConferencesWebexScript.Interfaces;

namespace ConferencesWebexScript.ApiTemplates
{
    internal class ConferenceRequestCreate : ICredentials
    {
        public string Event { get; set; }
        public DataCreate Data_create_update { get; set; }
    }
}
